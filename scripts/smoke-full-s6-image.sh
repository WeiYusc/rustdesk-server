#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${RUSTDESK_FULL_S6_IMAGE:-rustdesk-server-full-s6:local}"
CONTAINER_NAME="${RUSTDESK_FULL_S6_CONTAINER:-rustdesk-full-s6-smoke}"
API_PORT="${RUSTDESK_FULL_S6_API_PORT:-24114}"
HBBS_PORT="${RUSTDESK_FULL_S6_HBBS_PORT:-24116}"
HBBR_PORT="${RUSTDESK_FULL_S6_HBBR_PORT:-24117}"
DATA_DIR=""
APP_DATA_DIR=""
COOKIE_JAR=""

cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  [[ -n "${DATA_DIR}" ]] && rm -rf "${DATA_DIR}"
  [[ -n "${APP_DATA_DIR}" ]] && rm -rf "${APP_DATA_DIR}"
  [[ -n "${COOKIE_JAR}" ]] && rm -f "${COOKIE_JAR}"
}
trap cleanup EXIT

http_get() {
  curl -fsS "$1"
}

show_sanitized_logs() {
  docker logs "${CONTAINER_NAME}" 2>&1 \
    | sed -E 's/(Admin Password Is: )[[:graph:]]+/\1<redacted>/' \
    | tail -120
}

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 90); do
    if http_get "${url}" >/dev/null 2>&1; then
      return 0
    fi
    if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
      show_sanitized_logs >&2
      return 1
    fi
    sleep 1
  done
  show_sanitized_logs >&2
  echo "timed out waiting for ${url}" >&2
  return 1
}

DATA_DIR="$(mktemp -d -t rustdesk-full-s6-data.XXXXXX)"
APP_DATA_DIR="$(mktemp -d -t rustdesk-full-s6-appdata.XXXXXX)"
COOKIE_JAR="$(mktemp -t rustdesk-full-s6-cookie.XXXXXX)"

docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "127.0.0.1:${API_PORT}:21114/tcp" \
  -p "127.0.0.1:${HBBS_PORT}:21116/tcp" \
  -p "127.0.0.1:${HBBS_PORT}:21116/udp" \
  -p "127.0.0.1:${HBBR_PORT}:21117/tcp" \
  -v "${DATA_DIR}:/data" \
  -v "${APP_DATA_DIR}:/app/data" \
  -e "RELAY=127.0.0.1:21117" \
  -e "RUSTDESK_API_GIN_API_ADDR=0.0.0.0:21114" \
  -e "RUSTDESK_API_RUSTDESK_ID_SERVER=127.0.0.1:${HBBS_PORT}" \
  -e "RUSTDESK_API_RUSTDESK_RELAY_SERVER=127.0.0.1:${HBBR_PORT}" \
  -e "RUSTDESK_API_RUSTDESK_API_SERVER=http://127.0.0.1:${API_PORT}" \
  -e "RUSTDESK_API_RUSTDESK_KEY_FILE=/data/id_ed25519.pub" \
  -e "RUSTDESK_API_APP_CAPTCHA_THRESHOLD=-1" \
  -e "RUSTDESK_API_APP_BAN_THRESHOLD=0" \
  "${IMAGE_TAG}" >/dev/null

wait_for_http "http://127.0.0.1:${API_PORT}/api/version"
BUILD_INFO_JSON="$(http_get "http://127.0.0.1:${API_PORT}/api/build-info")"

for svc in hbbr hbbs api; do
  docker exec "${CONTAINER_NAME}" /command/s6-svstat "/run/s6-rc/servicedirs/${svc}" | grep -q '^up '
done

docker exec "${CONTAINER_NAME}" test -s /data/id_ed25519.pub
docker exec "${CONTAINER_NAME}" test -s /etc/rustdesk-full-s6-build.json
http_get "http://127.0.0.1:${API_PORT}/_admin/" >/dev/null

python3 - "${BUILD_INFO_JSON}" "${IMAGE_TAG}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
image = sys.argv[2]
if payload.get("code") not in (0, 200):
    raise SystemExit(f"unexpected build-info payload: {payload!r}")
data = payload.get("data") or {}
if data.get("image") != image:
    raise SystemExit(f"build-info image mismatch: {data!r}, want {image!r}")
missing = [key for key in ("server_commit", "api_commit", "web_commit", "built_at") if not data.get(key)]
if missing:
    raise SystemExit(f"build-info missing {missing}: {data!r}")
if data.get("source") != "/etc/rustdesk-full-s6-build.json":
    raise SystemExit(f"build-info source mismatch: {data!r}")
PY

ADMIN_PASSWORD="$(docker logs "${CONTAINER_NAME}" 2>&1 | sed -n 's/.*Admin Password Is: *//p' | tail -1 | awk '{print $1}' | tr -d '\r')"
if [[ -z "${ADMIN_PASSWORD}" ]]; then
  echo "failed to extract generated admin password" >&2
  show_sanitized_logs >&2
  exit 1
fi

LOGIN_JSON="$(curl -fsS -c "${COOKIE_JAR}" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"${ADMIN_PASSWORD}\"}" \
  "http://127.0.0.1:${API_PORT}/api/admin/login")"

ADMIN_TOKEN="$(python3 - "${LOGIN_JSON}" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
if payload.get("code") not in (0, 200):
    raise SystemExit(f"unexpected login payload: {payload!r}")
data = payload.get("data") or {}
token = data.get("token") or data.get("access_token") or ""
if not token:
    raise SystemExit(f"login payload missing token: {payload!r}")
print(token)
PY
)"

CURRENT_JSON="$(curl -fsS -H "api-token: ${ADMIN_TOKEN}" "http://127.0.0.1:${API_PORT}/api/admin/user/current")"
CONFIG_JSON="$(curl -fsS -H "api-token: ${ADMIN_TOKEN}" "http://127.0.0.1:${API_PORT}/api/admin/config/server")"

python3 - "${CURRENT_JSON}" "${CONFIG_JSON}" "${API_PORT}" <<'PY'
import json
import sys
current = json.loads(sys.argv[1])
config = json.loads(sys.argv[2])
api_port = sys.argv[3]
if current.get("code") not in (0, 200):
    raise SystemExit(f"unexpected current payload: {current!r}")
if config.get("code") not in (0, 200):
    raise SystemExit(f"unexpected config payload: {config!r}")
text = json.dumps(config, sort_keys=True)
if f"127.0.0.1:{api_port}" not in text:
    raise SystemExit(f"api port not reflected in config: {config!r}")
PY

printf 'FULL_S6_SMOKE_PASS image=%s api_port=%s hbbs_port=%s hbbr_port=%s\n' "${IMAGE_TAG}" "${API_PORT}" "${HBBS_PORT}" "${HBBR_PORT}"
