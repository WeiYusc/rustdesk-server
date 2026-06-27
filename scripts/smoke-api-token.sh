#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_SOURCE_DIR="${RUSTDESK_API_SOURCE_DIR:-${ROOT_DIR}/../reference-repos/WeiYusc_rustdesk-api}"
API_PORT="${SMOKE_API_PORT:-24114}"
# Default loopback API endpoint: 127.0.0.1:24114.
SMOKE_JWT_KEY="${SMOKE_JWT_KEY:-stage3b-test-key-change-me}"
SMOKE_ADMIN_PASSWORD="${SMOKE_ADMIN_PASSWORD:-stage3b-pass}"
COMPOSE=(docker compose -f docker/compose-baseline/compose.yml)
TMP_DIR=""
API_PID=""
VERIFY_DIR=""

cleanup() {
  local exit_code=$?
  if [[ -n "${API_PID}" ]]; then
    kill -- "-${API_PID}" >/dev/null 2>&1 || true
    kill "${API_PID}" >/dev/null 2>&1 || true
    wait "${API_PID}" >/dev/null 2>&1 || true
  fi
  (cd "${ROOT_DIR}" && docker compose -f docker/compose-baseline/compose.yml down -v --remove-orphans >/dev/null 2>&1 || true)
  if [[ -n "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
  if [[ -n "${VERIFY_DIR}" ]]; then
    rm -rf "${VERIFY_DIR}"
  fi
  exit "${exit_code}"
}
trap cleanup EXIT

assert_port_free() {
  python3 - "$1" <<'PY'
import socket
import sys
port = int(sys.argv[1])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", port))
    except OSError as exc:
        raise SystemExit(f"127.0.0.1:{port} is already in use: {exc}")
PY
}

require_file() {
  if [[ ! -e "$1" ]]; then
    echo "missing required path: $1" >&2
    exit 1
  fi
}

http_get() {
  python3 - "$1" <<'PY'
import sys
from urllib import request
with request.urlopen(sys.argv[1], timeout=2) as response:
    print(response.read().decode(), end="")
PY
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-120}"
  for _ in $(seq 1 "${attempts}"); do
    if http_get "${url}" >/dev/null 2>&1; then
      return 0
    fi
    if [[ -n "${API_PID}" ]] && ! kill -0 "${API_PID}" >/dev/null 2>&1; then
      echo "api process exited early" >&2
      sed -n '1,200p' "${TMP_DIR}/api.log" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "timed out waiting for ${url}" >&2
  return 1
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

require_file "${API_SOURCE_DIR}/go.mod"
require_file "${ROOT_DIR}/docker/compose-baseline/compose.yml"
require_file "${ROOT_DIR}/target/release/hbbs"
require_file "${ROOT_DIR}/target/release/hbbr"
require_file "${ROOT_DIR}/target"
assert_port_free "${API_PORT}"

TMP_DIR="$(mktemp -d -t rustdesk-stage3b-api.XXXXXX)"
mkdir -p "${TMP_DIR}/api"
cp -a "${API_SOURCE_DIR}/." "${TMP_DIR}/api/"
mkdir -p "${TMP_DIR}/api/data" "${TMP_DIR}/api/runtime"

cd "${ROOT_DIR}"
"${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
"${COMPOSE[@]}" build >/dev/null
"${COMPOSE[@]}" up -d >/dev/null
COMPOSE_HEALTH="$(wait_for_compose_health)"

cd "${TMP_DIR}/api"
export GOFLAGS=-mod=mod
export GOTOOLCHAIN=auto
export RUSTDESK_API_GIN_API_ADDR="127.0.0.1:${API_PORT}"
export RUSTDESK_API_JWT_KEY="${SMOKE_JWT_KEY}"
export RUSTDESK_API_JWT_EXPIRE_DURATION="168h"
export RUSTDESK_API_APP_CAPTCHA_THRESHOLD="-1"
export RUSTDESK_API_APP_BAN_THRESHOLD="0"
export RUSTDESK_API_APP_SHOW_SWAGGER="0"
export RUSTDESK_API_APP_WEB_CLIENT="0"
export RUSTDESK_API_RUSTDESK_ID_SERVER="127.0.0.1:23116"
export RUSTDESK_API_RUSTDESK_RELAY_SERVER="127.0.0.1:23117"
export RUSTDESK_API_RUSTDESK_API_SERVER="http://127.0.0.1:${API_PORT}"

go run ./cmd -c ./conf/config.yaml reset-admin-pwd "${SMOKE_ADMIN_PASSWORD}" >"${TMP_DIR}/reset.log" 2>&1
if ! grep -q "reset password success" "${TMP_DIR}/reset.log"; then
  echo "reset-admin-pwd did not report success" >&2
  sed -n '1,200p' "${TMP_DIR}/reset.log" >&2 || true
  exit 1
fi
python3 - "${TMP_DIR}/api/data/rustdeskapi.db" <<'PY'
import sqlite3
import sys
con = sqlite3.connect(sys.argv[1])
row = con.execute("select id, username, status from users where id = 1").fetchone()
if row != (1, "admin", 1):
    raise SystemExit(f"unexpected admin row: {row!r}")
PY

setsid go run ./cmd -c ./conf/config.yaml >"${TMP_DIR}/api.log" 2>&1 &
API_PID="$!"
wait_for_http "http://127.0.0.1:${API_PORT}/api/version"
VERSION_JSON="$(http_get "http://127.0.0.1:${API_PORT}/api/version")"

LOGIN_JSON="$(python3 - "${API_PORT}" "${SMOKE_ADMIN_PASSWORD}" <<'PY'
import json
import sys
from urllib import error, request
port, password = sys.argv[1], sys.argv[2]
payload = json.dumps({
    "username": "admin",
    "password": password,
    "id": "stage3b-device",
    "uuid": "stage3b-uuid",
    "type": "account",
    "deviceInfo": {"name": "stage3b", "os": "linux", "type": "client"},
}).encode()
req = request.Request(
    f"http://127.0.0.1:{port}/api/login",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    with request.urlopen(req, timeout=5) as response:
        print(response.read().decode(), end="")
except error.HTTPError as exc:
    body = exc.read().decode(errors="replace")
    print(f"login failed: HTTP {exc.code}: {body}", file=sys.stderr)
    raise
PY
)"

TOKEN_REPORT="$(python3 - "${LOGIN_JSON}" <<'PY'
import base64
import hashlib
import json
import sys
login = json.loads(sys.argv[1])
token = login.get("access_token", "")
if not token:
    raise SystemExit(f"missing access_token: {login}")
parts = token.split(".")
if len(parts) != 3:
    raise SystemExit("access_token is not a JWT")
payload = parts[1] + "=" * (-len(parts[1]) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload))
print(json.dumps({
    "login_type": login.get("type"),
    "user_name": login.get("user", {}).get("name"),
    "token_sha256": hashlib.sha256(token.encode()).hexdigest(),
    "claims": claims,
}, sort_keys=True))
PY
)"

cd "${ROOT_DIR}"
VERIFY_DIR="$(mktemp -d -t rustdesk-stage3b-rust.XXXXXX)"
cp -a . "${VERIFY_DIR}/repo"
rm -rf "${VERIFY_DIR}/repo/.git" "${VERIFY_DIR}/repo/target"
python3 - "${VERIFY_DIR}/repo/src/rendezvous_server.rs" "${LOGIN_JSON}" "${SMOKE_JWT_KEY}" <<'PY'
import json
import sys
path, login_json, key = sys.argv[1], sys.argv[2], sys.argv[3]
login = json.loads(login_json)
token = login["access_token"]
with open(path, "r", encoding="utf-8") as fh:
    text = fh.read()
marker = '    #[test]\n    fn punch_hole_login_gate_accepts_go_api_golden_token_when_enabled() {'
insert = f'''    #[test]\n    fn punch_hole_login_gate_accepts_live_api_issued_token_when_enabled() {{\n        let token = {json.dumps(token)};\n\n        assert!(authorize_punch_hole_token(true, {json.dumps(key)}, token).is_ok());\n    }}\n\n'''
if marker not in text:
    raise SystemExit("test insertion marker not found")
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text.replace(marker, insert + marker))
PY
docker run --rm \
  -v "${VERIFY_DIR}/repo:/work" \
  -v "${ROOT_DIR}/target:/work/target" \
  -w /work \
  rust:1-bookworm \
  bash -lc 'export PATH=/usr/local/cargo/bin:$PATH; cargo test --release punch_hole_login_gate_accepts_live_api_issued_token_when_enabled -- --nocapture' >/dev/null
rm -rf "${VERIFY_DIR}"
VERIFY_DIR=""

printf 'STAGE3B_SMOKE_PASS\n'
printf 'COMPOSE_HEALTH\n%s\n' "${COMPOSE_HEALTH}"
printf 'API_VERSION %s\n' "${VERSION_JSON}"
printf 'TOKEN_REPORT %s\n' "${TOKEN_REPORT}"
printf 'RUST_GATE_LIVE_TOKEN_TEST ok\n'
