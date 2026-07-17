# RustDesk full-s6 Integrated Image Deployment Guide

This guide is for operators deploying the `rustdesk-server-full-s6` integrated image for the first time. The image runs the following components in one s6-supervised container:

- `hbbs`: RustDesk ID/rendezvous server.
- `hbbr`: RustDesk relay server.
- `rustdesk-api`: account, address-book, audit, and admin API service.
- Web Admin: static admin frontend assets.

> Replace all example domains, addresses, secrets, and image tags with your own values. Never publish real passwords, tokens, private keys, JWT secrets, or unredacted screenshots.

## 1. Scope

This guide covers a single-host Docker deployment where:

- one container runs the server, API, and Web Admin services;
- data is persisted through host directories;
- the Web Admin is preferably exposed through an HTTPS domain;
- the current documented image target is `linux/amd64`.

If you only want to run the official `hbbs` and `hbbr` services separately, follow the upstream RustDesk self-hosting documentation instead.

## 2. Prerequisites

### 2.1 Ports

Open these ports as needed:

| Port | Protocol | Purpose |
| --- | --- | --- |
| `21114` | TCP | API service and Web Admin |
| `21115` | TCP | RustDesk server auxiliary port |
| `21116` | TCP/UDP | `hbbs` ID/rendezvous server |
| `21117` | TCP | `hbbr` relay server |
| `21118` | TCP | Web client related port, if used |
| `21119` | TCP | Web client related port, if used |

### 2.2 Data directories

Use stable host paths so upgrades and backups are predictable:

```text
/opt/rustdesk-full-s6/server-data  -> /data
/opt/rustdesk-full-s6/app-data     -> /app/data
```

Directory purpose:

- `/data`: RustDesk server keys such as `id_ed25519` and `id_ed25519.pub`.
- `/app/data`: API database, uploaded files, and runtime data.

> Do not delete these directories during upgrades. Removing them may break client key matching or lose Web Admin/API data.

### 2.3 Generate a JWT secret

`RUSTDESK_API_JWT_KEY` signs and validates login tokens. The command below generates 32 random bytes and prints them as 64 hex characters:

```bash
openssl rand -hex 32
```

Store it securely. Do not paste it into public documentation, screenshots, or issue reports.


## Image tag policy

- `v0.1.0`: stable version for reproducible deployment, troubleshooting, and rollback.
- `latest`: moving stable tag that follows the newest stable release; confirm you accept a moving tag before using it in automation.
- `preview`: preview channel for test environments that intentionally follow preview updates; it is not automatically equivalent to stable.

## 3. Start the container

If you want to copy a `docker-compose.yml` and `.env` template, start with the [Docker Compose template](compose.en.md). The `docker run` example below is useful for manual deployment or understanding each option.

Replace `<your-host-or-ip>`, `<your-domain>`, `<random-64-hex-character-secret>`, and `<tag>` with your deployment values.

```bash
docker run -d \
  --name rustdesk-full-s6 \
  --restart unless-stopped \
  -p 21114:21114/tcp \
  -p 21115:21115/tcp \
  -p 21116:21116/tcp \
  -p 21116:21116/udp \
  -p 21117:21117/tcp \
  -p 21118:21118/tcp \
  -p 21119:21119/tcp \
  -v /opt/rustdesk-full-s6/server-data:/data \
  -v /opt/rustdesk-full-s6/app-data:/app/data \
  -e RELAY=<your-host-or-ip>:21117 \
  -e RUSTDESK_API_RUSTDESK_ID_SERVER=<your-host-or-ip>:21116 \
  -e RUSTDESK_API_RUSTDESK_RELAY_SERVER=<your-host-or-ip>:21117 \
  -e RUSTDESK_API_RUSTDESK_API_SERVER=https://<your-domain> \
  -e RUSTDESK_API_RUSTDESK_KEY_FILE=/data/id_ed25519.pub \
  -e RUSTDESK_API_JWT_KEY=<random-64-hex-character-secret> \
  ghcr.io/weiyusc/rustdesk-server-full-s6:<tag>
```

For a temporary local check, `http://<your-host-or-ip>:21114` can be used as the API server URL. For external use, HTTPS is recommended.

## 4. Common environment variables

| Variable | Meaning | Example |
| --- | --- | --- |
| `RELAY` | Relay address returned by `hbbs` to clients | `<your-host-or-ip>:21117` |
| `RUSTDESK_API_RUSTDESK_ID_SERVER` | ID server shown in Web Admin client configuration | `<your-host-or-ip>:21116` |
| `RUSTDESK_API_RUSTDESK_RELAY_SERVER` | Relay server shown in Web Admin client configuration | `<your-host-or-ip>:21117` |
| `RUSTDESK_API_RUSTDESK_API_SERVER` | API URL used by client login and browser authorization | `https://<your-domain>` |
| `RUSTDESK_API_RUSTDESK_KEY_FILE` | Server public key path | `/data/id_ed25519.pub` |
| `RUSTDESK_API_JWT_KEY` | Login-token signing secret | a random value |
| `MUST_LOGIN` | Default forced-login state at container startup | `Y` or `N` |
| `RUSTDESK_API_GIN_TRUST_PROXY` | Trusted reverse proxy address for API/Web Admin when Nginx, BT Panel, or Caddy proxies to the API locally | `127.0.0.1` |
| `RUSTDESK_ONLINE_FALLBACK_API_HEARTBEAT` | Full-s6 address-book online fallback from recent API heartbeat timestamps | `Y` |
| `RUSTDESK_ONLINE_FALLBACK_API_DB` | SQLite DB path used by the full-s6 online fallback | `/app/data/rustdeskapi.db` |
| `RUSTDESK_ONLINE_FALLBACK_API_HEARTBEAT_TTL` | Maximum heartbeat age in seconds for the online fallback | `60` |

Notes:

- `RUSTDESK_API_JWT_KEY` is required when `MUST_LOGIN` is enabled. The API uses it to sign client login tokens, and `hbbs` validates tokens with the same value. If it is missing or inconsistent, clients can log in with password or WebAuth but still fail connections with `login-required`; hbbs usually logs `invalid login token`.
- `MUST_LOGIN` is the startup default. The Web Admin toggle applies an `hbbs` runtime command immediately; after the container or `hbbs` restarts, the environment variable default applies again.
- Set `RUSTDESK_API_GIN_TRUST_PROXY=127.0.0.1` when API/Web Admin is served through a local reverse proxy. Otherwise Gin sees the proxy as the client and Web Admin login logs plus device `last_online_ip` may show `127.0.0.1`. Only trust proxy addresses you control; do not use broad values when exposing the API port directly.
- In the full-s6 image, `RUSTDESK_ONLINE_FALLBACK_API_HEARTBEAT=Y` lets hbbs answer 21115 address-book `OnlineRequest` from recent API heartbeat timestamps when native hbbs in-memory presence has expired. It is a UI presence fallback only: it does not grant authentication, authorization, or connection permission. The default SQLite path is `/app/data/rustdeskapi.db`; MySQL deployments need a separate compatible heartbeat source before using this fallback.
- If Compose `secrets` mount `id_ed25519` / `id_ed25519.pub`, both files must be a valid RustDesk Ed25519 server key pair. Client Key must come from the same `id_ed25519.pub`; changing the pair requires updating clients.
- For MySQL, key creation, required/optional parameters, and failure modes, see the [Docker Compose template](compose.en.md#8-parameters-and-common-failure-modes). For first deployment, start with the default SQLite path until the basic stack works, then switch to MySQL if needed.

## 5. First login and password reset

On first boot, the API service normally prints a random admin password in the container logs. Read it only from a secure terminal:

```bash
docker logs rustdesk-full-s6 2>&1 | grep -i 'Admin Password' | tail -1
```

If the admin password is lost, reset it inside the container:

```bash
docker exec -w /app rustdesk-full-s6 \
  /app/apimain -c /app/conf/config.yaml reset-admin-pwd '<new-password>'
```

Use a strong replacement password.

## 6. Client configuration

After logging into Web Admin, open **Profile / Server connection credentials** and copy the client import configuration. Confirm that the client has the correct:

- ID server;
- relay server;
- API server;
- Key/public-key value;
- account login state before enabling forced login.

For client login, forced login, and error-matrix troubleshooting, see:

- [Client login, MUST_LOGIN, and server configuration troubleshooting](https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.en.md)

## 7. Post-deployment checks

### 7.1 Container health

```bash
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}}'
```

Expected:

```text
status=running health=healthy
```

### 7.2 API service

```bash
curl -fsS http://127.0.0.1:21114/api/version
curl -fsS http://127.0.0.1:21114/api/build-info
```

`/api/build-info` returns the server, API, and Web Admin source fingerprints embedded in the image.

### 7.3 Web Admin

```bash
curl -fsSI http://127.0.0.1:21114/_admin/ | head -5
```

If an HTTPS domain is configured, also check:

```bash
curl -fsSI https://<your-domain>/_admin/ | head -5
```

### 7.4 Listeners

```bash
ss -lntup | grep -E ':2111[4-9]'
ss -lnuap | grep ':21116'
```

## 8. Security notes

- Use HTTPS for external access.
- Do not publish real domains, IPs, Keys, tokens, admin passwords, or unredacted screenshots.
- Expose only required ports through the firewall.
- Before upgrading, back up `/data` and `/app/data` by following the [upgrade and rollback guide](upgrade-rollback.en.md).
- If enabling `MUST_LOGIN=Y`, validate both logged-in and logged-out client behavior first.
- The current integrated image still follows the s6 pattern and starts as root inside the container. Non-root runtime is a later hardening task.

## 9. Known limits

- The current stable image only claims validated `linux/amd64` support.
- `linux/arm64` and multi-architecture images are not published or claimed in this release; they require separate runtime validation later.
- `latest` is the moving stable tag; pin `v0.1.0` or a digest when reproducibility matters.
- The forced-login runtime toggle is not stored in the database; restart behavior follows the environment variable.
- The full real official-client matrix was not rerun for this stable release; it carries forward the existing accepted client-matrix evidence.
- Real client connection behavior depends on client version, network conditions, and server configuration.
