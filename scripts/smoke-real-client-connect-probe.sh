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
TARGET_PID=""

cleanup() {
  local exit_code=$?
  if [[ -n "${TARGET_PID}" ]]; then
    kill -- "-${TARGET_PID}" >/dev/null 2>&1 || true
    kill "${TARGET_PID}" >/dev/null 2>&1 || true
    wait "${TARGET_PID}" >/dev/null 2>&1 || true
  fi
  rm -rf /tmp/RustDesk-0
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

require_client_runtime_libs() {
  if ! ldconfig -p | grep -Eq 'libayatana-appindicator3|libappindicator3'; then
    echo "missing RustDesk AppImage tray runtime library: install libayatana-appindicator3-1 or libappindicator3-1" >&2
    exit 1
  fi
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

wait_for_compose_health() {
  for _ in $(seq 1 90); do
    local statuses
    statuses="$(docker inspect rustdesk-server-baseline-hbbr-1 rustdesk-server-baseline-hbbs-1 --format '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null || true)"
    if [[ "$(grep -c ' healthy' <<<"${statuses}" || true)" == "2" ]]; then
      printf '%s\n' "${statuses}"
      return 0
    fi
    sleep 1
  done
  echo "compose baseline did not become healthy" >&2
  return 1
}

wait_for_log() {
  local file="$1"
  local pattern="$2"
  local attempts="$3"
  for _ in $(seq 1 "${attempts}"); do
    if grep -qF "${pattern}" "${file}" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for log pattern: ${pattern}" >&2
  sed -n '1,220p' "${file}" >&2 || true
  return 1
}

write_client_config() {
  local dir="$1"
  mkdir -p "${dir}/.config/rustdesk"
  cat > "${dir}/.config/rustdesk/RustDesk2.toml" <<'EOF'
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
}

require_file "${ROOT_DIR}/docker/compose-baseline/compose.yml"
require_file "${ROOT_DIR}/target/release/hbbs"
require_file "${ROOT_DIR}/target/release/hbbr"
command -v xvfb-run >/dev/null
command -v curl >/dev/null
require_client_runtime_libs
download_client

TMP_DIR="$(mktemp -d -t rustdesk-stage3d-connect.XXXXXX)"
TARGET_HOME="${TMP_DIR}/target-home"
CALLER_HOME="${TMP_DIR}/caller-home"
write_client_config "${TARGET_HOME}"
write_client_config "${CALLER_HOME}"

cd "${ROOT_DIR}"
"${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
"${COMPOSE[@]}" build >/dev/null
"${COMPOSE[@]}" up -d >/dev/null
COMPOSE_HEALTH="$(wait_for_compose_health)"

rm -rf /tmp/RustDesk-0
mkdir -p "${TMP_DIR}/target-run"
(
  cd "${TMP_DIR}/target-run"
  exec setsid env HOME="${TARGET_HOME}" XDG_CONFIG_HOME="${TARGET_HOME}/.config" timeout "${CLIENT_TIMEOUT}" xvfb-run -a "${APPIMAGE}" --server
) >"${TMP_DIR}/target-wrapper.log" 2>&1 &
TARGET_PID="$!"
TARGET_LOG="${TARGET_HOME}/.local/share/logs/RustDesk/server/rustdesk_rCURRENT.log"
wait_for_log "${TARGET_LOG}" "register_pk of 127.0.0.1:23116" 35
TARGET_ID="$(grep -Eo 'Generated id [0-9]+' "${TARGET_LOG}" | tail -1 | awk '{print $3}')"
TARGET_ID="${TARGET_ID:-352321600}"

rm -rf /tmp/RustDesk-0
mkdir -p "${TMP_DIR}/caller-run"
(
  cd "${TMP_DIR}/caller-run"
  HOME="${CALLER_HOME}" XDG_CONFIG_HOME="${CALLER_HOME}/.config" timeout 35 xvfb-run -a "${APPIMAGE}" --connect "${TARGET_ID}"
) >"${TMP_DIR}/caller-wrapper.log" 2>&1 || true
CALLER_LOG="${CALLER_HOME}/.local/share/logs/RustDesk/flutter_ffi/rustdesk_rCURRENT.log"
wait_for_log "${CALLER_LOG}" "TCP punch attempt" 5
wait_for_log "${CALLER_LOG}" "Key mismatch" 5
if ! docker logs rustdesk-server-baseline-hbbs-1 2>&1 | grep -qi "invalid key"; then
  echo "hbbs log did not contain invalid key boundary" >&2
  docker logs --tail 240 rustdesk-server-baseline-hbbs-1 >&2 || true
  exit 1
fi

CALLER_SUMMARY="$(grep -E 'rendezvous server: 127.0.0.1:23116|TCP punch attempt|Key mismatch' "${CALLER_LOG}" | tail -20)"
HBBS_BOUNDARY="$(docker logs rustdesk-server-baseline-hbbs-1 2>&1 | grep -i 'invalid key' | tail -1)"

printf 'SMOKE_REAL_CLIENT_CONNECT_PROBE_BOUNDARY\n'
printf 'COMPOSE_HEALTH\n%s\n' "${COMPOSE_HEALTH}"
printf 'TARGET_ID %s\n' "${TARGET_ID}"
printf 'CALLER_SUMMARY\n%s\n' "${CALLER_SUMMARY}"
printf 'HBBS_BOUNDARY %s\n' "${HBBS_BOUNDARY}"
printf 'LIMITATION two-client login/connect remains unverified: same-host AppImage clients share machine-derived identity/key context and currently stop at Key mismatch before login/token UX.\n'
