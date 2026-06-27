# Full-s6 Integrated Image

This packaging path builds a single s6-overlay Docker image containing:

- `hbbr`
- `hbbs`
- `rustdesk-api`
- the built `rustdesk-api-web` admin frontend under `/app/resources/admin`

It is intentionally additive and does not replace the existing `docker/compose-baseline/` verification path.

## Build

From the server repository root:

```bash
./scripts/build-full-s6-image.sh
```

Default inputs:

- Server repo: current directory.
- API repo: `../reference-repos/WeiYusc_rustdesk-api`.
- Admin web repo: `../reference-repos/WeiYusc_rustdesk-api-web`.
- Image tag: `rustdesk-server-full-s6:local`.

Overrides:

```bash
RUSTDESK_API_SOURCE_DIR=/path/to/rustdesk-api \
RUSTDESK_API_WEB_SOURCE_DIR=/path/to/rustdesk-api-web \
RUSTDESK_FULL_S6_IMAGE=example/rustdesk-server-full-s6:dev \
./scripts/build-full-s6-image.sh
```

The build script copies the API repo into a temporary directory before running `go build` because the current API module requires `GOFLAGS=-mod=mod`, which can rewrite `go.mod` if run directly in the source checkout.

The Dockerfile verifies the downloaded s6-overlay tarballs before extraction. The default checksum arguments cover the local x86_64 build path. If you override `S6_OVERLAY_VERSION`, provide matching `S6_OVERLAY_NOARCH_SHA256` and `S6_OVERLAY_ARCH_SHA256`; if you override `S6_ARCH`, also provide the matching `S6_OVERLAY_ARCH_SHA256`. Non-default architectures without an explicit architecture checksum fail closed instead of extracting an unverified tarball.

## Smoke Test

```bash
./scripts/smoke-full-s6-image.sh
```

The smoke test runs the image with loopback-only port mappings and verifies:

- s6 starts as PID 1 through `/init`.
- `hbbr`, `hbbs`, and `api` are up under s6.
- RustDesk server key material is generated in `/data`.
- `/_admin/` returns HTTP 200.
- Admin login works using the generated first-run password from the API logs.
- `/api/admin/user/current` and `/api/admin/config/server` work with the returned admin token.

Default test ports:

- API: `127.0.0.1:24114 -> 21114/tcp`
- hbbs TCP/UDP: `127.0.0.1:24116 -> 21116/tcp+udp`
- hbbr TCP: `127.0.0.1:24117 -> 21117/tcp`

Overrides:

```bash
RUSTDESK_FULL_S6_API_PORT=25114 \
RUSTDESK_FULL_S6_HBBS_PORT=25116 \
RUSTDESK_FULL_S6_HBBR_PORT=25117 \
./scripts/smoke-full-s6-image.sh
```

## Runtime Example

Replace the placeholder hostnames and URLs with deployment-specific values:

```bash
docker run -d \
  --name rustdesk-full-s6 \
  -p 21114:21114/tcp \
  -p 21115:21115/tcp \
  -p 21116:21116/tcp \
  -p 21116:21116/udp \
  -p 21117:21117/tcp \
  -p 21118:21118/tcp \
  -p 21119:21119/tcp \
  -v rustdesk-data:/data \
  -v rustdesk-api-data:/app/data \
  -e RELAY=relay.example.com:21117 \
  -e RUSTDESK_API_RUSTDESK_ID_SERVER=id.example.com:21116 \
  -e RUSTDESK_API_RUSTDESK_RELAY_SERVER=relay.example.com:21117 \
  -e RUSTDESK_API_RUSTDESK_API_SERVER=https://api.example.com \
  -e RUSTDESK_API_RUSTDESK_KEY_FILE=/data/id_ed25519.pub \
  rustdesk-server-full-s6:local
```

Optional key injection follows the upstream s6-compatible behavior:

- Docker secrets: `/run/secrets/key_pub` and `/run/secrets/key_priv`.
- Environment variables: `KEY_PUB` and `KEY_PRIV`.

If neither is provided, `hbbs` generates a new keypair in `/data` on first boot.

## Runtime Hardening Boundary

The integrated image currently follows the upstream s6-overlay pattern and starts as root so PID 1 supervision, key injection, key ownership fixes, and mounted `/data` / `/app/data` writes continue to work. A non-root runtime remains a separate hardening slice that must be paired with image smoke validation and volume ownership handling.

## Verification Boundary

The current local verification proves the integrated image builds and the installed admin/API/server processes run together under s6. It does **not** yet prove a real two-client RustDesk forced-login connection flow. Keep the real-client login/connect matrix row `Partial` until distinct-client validation or an equivalent protocol harness is available.
