#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUSTDESK_CLIENT_APPIMAGE_URL="${RUSTDESK_CLIENT_APPIMAGE_URL:-https://github.com/rustdesk/rustdesk/releases/download/1.4.8/rustdesk-1.4.8-x86_64.AppImage}"
RUSTDESK_CLIENT_APPIMAGE_SHA256="${RUSTDESK_CLIENT_APPIMAGE_SHA256:-}"
CACHE_DIR="${RUSTDESK_CLIENT_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/rustdesk-server-smoke}"
APPIMAGE="${RUSTDESK_CLIENT_APPIMAGE:-${CACHE_DIR}/rustdesk-1.4.8-x86_64.AppImage}"
CLIENT_TIMEOUT="${SMOKE_CLIENT_TIMEOUT:-45}"
COMPOSE=(docker compose -f docker/compose-baseline/compose.yml)
TMP_DIR=""
CLIENT_SESSION_PID=""

cleanup() {
  local exit_code=$?
  if [[ -n "${CLIENT_SESSION_PID}" ]]; then
    kill -- "-${CLIENT_SESSION_PID}" >/dev/null 2>&1 || true
    kill "${CLIENT_SESSION_PID}" >/dev/null 2>&1 || true
    wait "${CLIENT_SESSION_PID}" >/dev/null 2>&1 || true
  fi
  (cd "${ROOT_DIR}" && docker compose -f docker/compose-baseline/compose.yml down -v --remove-orphans >/dev/null 2>&1 || true)
  if [[ -n "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
  exit "${exit_code}"
}
trap cleanup EXIT

require_file() {
  if [[ ! -e "$1" ]]; then
    echo "missing required path: $1" >&2
    exit 1
  fi
}

wait_for_compose_health() {
  for _ in $(seq 1 90); do
    local statuses
    statuses="$(docker inspect rustdesk-server-baseline-hbbr-1 rustdesk-server-baseline-hbbs-1 --format '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null || true)"
    if [[ "$(grep -c ' healthy' <<<"${statuses}" || true)" == "2" ]]; then
      printf '%s\n' "${statuses}"
      return 0
    fi
    if grep -qE 'unhealthy|exited' <<<"${statuses}"; then
      printf '%s\n' "${statuses}" >&2
      return 1
    fi
    sleep 1
  done
  echo "compose baseline did not become healthy" >&2
  return 1
}

download_client() {
  mkdir -p "${CACHE_DIR}"
  if [[ ! -x "${APPIMAGE}" ]]; then
    curl -L --fail --connect-timeout 20 --max-time 180 -o "${APPIMAGE}.tmp" "${RUSTDESK_CLIENT_APPIMAGE_URL}"
    if [[ -n "${RUSTDESK_CLIENT_APPIMAGE_SHA256}" ]]; then
      printf '%s  %s\n' "${RUSTDESK_CLIENT_APPIMAGE_SHA256}" "${APPIMAGE}.tmp" | sha256sum -c -
    fi
    mv "${APPIMAGE}.tmp" "${APPIMAGE}"
    chmod +x "${APPIMAGE}"
  elif [[ -n "${RUSTDESK_CLIENT_APPIMAGE_SHA256}" ]]; then
    printf '%s  %s\n' "${RUSTDESK_CLIENT_APPIMAGE_SHA256}" "${APPIMAGE}" | sha256sum -c -
  fi
  require_file "${APPIMAGE}"
}

require_client_runtime_libs() {
  if ! ldconfig -p | grep -Eq 'libayatana-appindicator3|libappindicator3'; then
    echo "missing RustDesk AppImage tray runtime library: install libayatana-appindicator3-1 or libappindicator3-1" >&2
    exit 1
  fi
}

wait_for_log() {
  local file="$1"
  local pattern="$2"
  local attempts="$3"
  for _ in $(seq 1 "${attempts}"); do
    if grep -qF "${pattern}" "${file}" 2>/dev/null; then
      return 0
    fi
    if [[ -n "${CLIENT_SESSION_PID}" ]] && ! kill -0 "${CLIENT_SESSION_PID}" >/dev/null 2>&1; then
      echo "client process exited before log pattern appeared: ${pattern}" >&2
      sed -n '1,240p' "${file}" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "timed out waiting for log pattern: ${pattern}" >&2
  sed -n '1,240p' "${file}" >&2 || true
  return 1
}

require_file "${ROOT_DIR}/docker/compose-baseline/compose.yml"
require_file "${ROOT_DIR}/target/release/hbbs"
require_file "${ROOT_DIR}/target/release/hbbr"
command -v xvfb-run >/dev/null
command -v curl >/dev/null
require_client_runtime_libs

download_client
TMP_DIR="$(mktemp -d -t rustdesk-stage3c-client.XXXXXX)"
CLIENT_HOME="${TMP_DIR}/home"
rm -rf /tmp/RustDesk-0
mkdir -p "${CLIENT_HOME}/.config/rustdesk"
cat > "${CLIENT_HOME}/.config/rustdesk/RustDesk2.toml" <<'EOF'
rendezvous_server = '127.0.0.1:23116'
nat_type = 1
serial = 0
unlock_pin = ''
trusted_devices = ''

[options]
custom-rendezvous-server = '127.0.0.1:23116'
relay-server = '127.0.0.1:23117'
api-server = 'http://127.0.0.1:24114'
EOF

cd "${ROOT_DIR}"
"${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
"${COMPOSE[@]}" build >/dev/null
"${COMPOSE[@]}" up -d >/dev/null
COMPOSE_HEALTH="$(wait_for_compose_health)"

CLIENT_LOG="${CLIENT_HOME}/.local/share/logs/RustDesk/server/rustdesk_rCURRENT.log"
(
  cd "${TMP_DIR}"
  exec setsid env HOME="${CLIENT_HOME}" XDG_CONFIG_HOME="${CLIENT_HOME}/.config" timeout "${CLIENT_TIMEOUT}" xvfb-run -a "${APPIMAGE}" --server
) >"${TMP_DIR}/client-wrapper.log" 2>&1 &
CLIENT_SESSION_PID="$!"

wait_for_log "${CLIENT_LOG}" "start rendezvous mediator of 127.0.0.1:23116" 30
wait_for_log "${CLIENT_LOG}" "register_pk of 127.0.0.1:23116" 30
wait_for_log "${CLIENT_LOG}" "HTTP POST to http://127.0.0.1:24114/api/sysinfo failed" 30
if ! docker logs rustdesk-server-baseline-hbbs-1 2>&1 | grep -q "update_pk"; then
  echo "hbbs log did not contain update_pk from real client" >&2
  docker logs --tail 200 rustdesk-server-baseline-hbbs-1 >&2 || true
  exit 1
fi

CLIENT_CONFIG="$(sed -n '1,30p' "${CLIENT_HOME}/.config/rustdesk/RustDesk2.toml")"
CLIENT_LOG_SUMMARY="$(grep -E 'start rendezvous mediator|register_pk|HTTP POST to http://127.0.0.1:24114/api/sysinfo failed' "${CLIENT_LOG}" | tail -20)"
HBBS_UPDATE="$(docker logs rustdesk-server-baseline-hbbs-1 2>&1 | grep 'update_pk' | tail -1)"

printf 'SMOKE_REAL_CLIENT_REGISTER_PASS\n'
printf 'COMPOSE_HEALTH\n%s\n' "${COMPOSE_HEALTH}"
printf 'CLIENT_CONFIG\n%s\n' "${CLIENT_CONFIG}"
printf 'CLIENT_LOG_SUMMARY\n%s\n' "${CLIENT_LOG_SUMMARY}"
printf 'HBBS_UPDATE %s\n' "${HBBS_UPDATE}"
printf 'LIMITATION real two-client login/connect and PunchHoleRequest.token propagation still require an interactive/UI or protocol harness.\n'
