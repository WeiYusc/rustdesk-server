#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_SOURCE_DIR="${RUSTDESK_API_SOURCE_DIR:-${ROOT_DIR}/../reference-repos/WeiYusc_rustdesk-api}"
WEB_SOURCE_DIR="${RUSTDESK_API_WEB_SOURCE_DIR:-${ROOT_DIR}/../reference-repos/WeiYusc_rustdesk-api-web}"
IMAGE_TAG="${RUSTDESK_FULL_S6_IMAGE:-rustdesk-server-full-s6:local}"
BUILD_DIR=""

cleanup() {
  if [[ -n "${BUILD_DIR}" ]]; then
    rm -rf "${BUILD_DIR}"
  fi
}
trap cleanup EXIT

require_file() {
  if [[ ! -e "$1" ]]; then
    echo "missing required path: $1" >&2
    exit 1
  fi
}

require_executable() {
  if [[ ! -x "$1" ]]; then
    echo "missing executable: $1" >&2
    exit 1
  fi
}

require_executable "${ROOT_DIR}/target/release/hbbs"
require_executable "${ROOT_DIR}/target/release/hbbr"
require_executable "${ROOT_DIR}/target/release/rustdesk-utils"
require_file "${API_SOURCE_DIR}/go.mod"
require_file "${WEB_SOURCE_DIR}/package.json"
require_file "${ROOT_DIR}/docker/full-s6/Dockerfile"

git_short_sha() {
  local repo_dir="$1"
  if git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${repo_dir}" rev-parse --short=7 HEAD
  else
    printf 'unknown'
  fi
}

SERVER_COMMIT="${RUSTDESK_FULL_S6_SERVER_COMMIT:-$(git_short_sha "${ROOT_DIR}")}"
API_COMMIT="${RUSTDESK_FULL_S6_API_COMMIT:-$(git_short_sha "${API_SOURCE_DIR}")}"
WEB_COMMIT="${RUSTDESK_FULL_S6_WEB_COMMIT:-$(git_short_sha "${WEB_SOURCE_DIR}")}"
BUILT_AT="${RUSTDESK_FULL_S6_BUILT_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

BUILD_DIR="$(mktemp -d -t rustdesk-full-s6-build.XXXXXX)"
mkdir -p \
  "${BUILD_DIR}/server-bin" \
  "${BUILD_DIR}/api-src" \
  "${BUILD_DIR}/web-src" \
  "${BUILD_DIR}/api-bin" \
  "${BUILD_DIR}/api-runtime/resources/admin" \
  "${BUILD_DIR}/rootfs"

cp "${ROOT_DIR}/target/release/hbbs" "${BUILD_DIR}/server-bin/hbbs"
cp "${ROOT_DIR}/target/release/hbbr" "${BUILD_DIR}/server-bin/hbbr"
cp "${ROOT_DIR}/target/release/rustdesk-utils" "${BUILD_DIR}/server-bin/rustdesk-utils"
cp -a "${API_SOURCE_DIR}/." "${BUILD_DIR}/api-src/"
rm -rf "${BUILD_DIR}/api-src/.git" "${BUILD_DIR}/api-src/data" "${BUILD_DIR}/api-src/runtime"
cp -a "${WEB_SOURCE_DIR}/." "${BUILD_DIR}/web-src/"
rm -rf "${BUILD_DIR}/web-src/.git" "${BUILD_DIR}/web-src/dist" "${BUILD_DIR}/web-src/node_modules"

(
  cd "${BUILD_DIR}/api-src"
  GOFLAGS=-mod=mod GOTOOLCHAIN=auto go build -o "${BUILD_DIR}/api-bin/apimain" ./cmd
)

(
  cd "${BUILD_DIR}/web-src"
  CI=true pnpm install --frozen-lockfile
  CI=true pnpm build
)

cp -a "${API_SOURCE_DIR}/conf" "${BUILD_DIR}/api-runtime/conf"
cp -a "${API_SOURCE_DIR}/resources/." "${BUILD_DIR}/api-runtime/resources/"
rm -rf "${BUILD_DIR}/api-runtime/resources/admin"
mkdir -p "${BUILD_DIR}/api-runtime/resources/admin"
cp -a "${BUILD_DIR}/web-src/dist/." "${BUILD_DIR}/api-runtime/resources/admin/"
rm -rf "${BUILD_DIR}/api-src" "${BUILD_DIR}/web-src"
cp -a "${ROOT_DIR}/docker/full-s6/rootfs/." "${BUILD_DIR}/rootfs/"
cp "${ROOT_DIR}/docker/full-s6/healthcheck.sh" "${BUILD_DIR}/healthcheck.sh"
cp "${ROOT_DIR}/docker/full-s6/Dockerfile" "${BUILD_DIR}/Dockerfile"
python3 - "${BUILD_DIR}/build-info.json" "${SERVER_COMMIT}" "${API_COMMIT}" "${WEB_COMMIT}" "${IMAGE_TAG}" "${BUILT_AT}" <<'PY'
import json
import sys

path, server, api, web, image, built_at = sys.argv[1:]
with open(path, "w", encoding="utf-8") as fh:
    json.dump(
        {
            "server_commit": server,
            "api_commit": api,
            "web_commit": web,
            "image": image,
            "built_at": built_at,
        },
        fh,
        sort_keys=True,
    )
    fh.write("\n")
PY

UNEXPECTED_ARTIFACTS="$(find "${BUILD_DIR}" \( -name .git -o -name node_modules -o -name rustdeskapi.db \) -print -prune)"
if [[ -n "${UNEXPECTED_ARTIFACTS}" ]]; then
  printf 'unexpected build artifact:\n%s\n' "${UNEXPECTED_ARTIFACTS}" >&2
  exit 1
fi

docker build \
  --build-arg "RUSTDESK_FULL_S6_SERVER_COMMIT=${SERVER_COMMIT}" \
  --build-arg "RUSTDESK_FULL_S6_API_COMMIT=${API_COMMIT}" \
  --build-arg "RUSTDESK_FULL_S6_WEB_COMMIT=${WEB_COMMIT}" \
  --build-arg "RUSTDESK_FULL_S6_IMAGE=${IMAGE_TAG}" \
  --build-arg "RUSTDESK_FULL_S6_BUILT_AT=${BUILT_AT}" \
  -t "${IMAGE_TAG}" "${BUILD_DIR}"

printf 'FULL_S6_IMAGE_BUILT %s\n' "${IMAGE_TAG}"
printf 'FULL_S6_BUILD_INFO server=%s api=%s web=%s image=%s built_at=%s\n' \
  "${SERVER_COMMIT}" "${API_COMMIT}" "${WEB_COMMIT}" "${IMAGE_TAG}" "${BUILT_AT}"
docker image inspect "${IMAGE_TAG}" --format 'IMAGE_ID {{.Id}}'
