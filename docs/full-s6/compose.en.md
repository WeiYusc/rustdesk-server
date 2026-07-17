# RustDesk full-s6 Docker Compose Template

This guide is for operators who prefer deploying `rustdesk-server-full-s6` with Docker Compose. Compose is easier to copy, persist, and upgrade than a long `docker run` command.

> Replace all example domains, addresses, and secrets with your own values. Do not commit your real `.env` file to a public repository.

## 1. Prepare a directory

```bash
mkdir -p rustdesk-full-s6/data/server rustdesk-full-s6/data/app
cd rustdesk-full-s6
```

Directory purpose:

- `./data/server`: RustDesk server keys, mounted as `/data`.
- `./data/app`: API database, uploads, and runtime data, mounted as `/app/data`.

## 2. Copy `docker-compose.yml`

Save this as:

```text
docker-compose.yml
```

```yaml
services:
  rustdesk-full-s6:
    image: ${RUSTDESK_FULL_S6_IMAGE:-ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0}
    container_name: rustdesk-full-s6
    restart: unless-stopped
    ports:
      - "21114:21114/tcp"
      - "21115:21115/tcp"
      - "21116:21116/tcp"
      - "21116:21116/udp"
      - "21117:21117/tcp"
      - "21118:21118/tcp"
      - "21119:21119/tcp"
    volumes:
      - ./data/server:/data
      - ./data/app:/app/data
    environment:
      RELAY: ${PUBLIC_HOST:?set PUBLIC_HOST}:21117
      RUSTDESK_API_RUSTDESK_ID_SERVER: ${PUBLIC_HOST:?set PUBLIC_HOST}:21116
      RUSTDESK_API_RUSTDESK_RELAY_SERVER: ${PUBLIC_HOST:?set PUBLIC_HOST}:21117
      RUSTDESK_API_RUSTDESK_API_SERVER: ${API_SERVER:?set API_SERVER}
      RUSTDESK_API_RUSTDESK_KEY_FILE: /data/id_ed25519.pub
      RUSTDESK_API_JWT_KEY: ${RUSTDESK_API_JWT_KEY:?set RUSTDESK_API_JWT_KEY}
      MUST_LOGIN: ${MUST_LOGIN:-N}
    healthcheck:
      test: ["CMD", "/usr/bin/healthcheck.sh"]
      interval: 10s
      timeout: 5s
      retries: 12
```

## 3. Copy the `.env` template

Save this as:

```text
.env
```

Then edit `PUBLIC_HOST`, `API_SERVER`, and `RUSTDESK_API_JWT_KEY`. If the placeholder domains are left unchanged, the container may start, but clients will not connect to your server correctly.

```env
# RustDesk full-s6 integrated image.
# Prefer an explicit stable tag or digest. latest follows the newest stable release; preview remains for preview testing.
RUSTDESK_FULL_S6_IMAGE=ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0

# Public host or IP that RustDesk clients can reach for hbbs/hbbr.
# Do not include a scheme or port here.
PUBLIC_HOST=your-server.example.com

# Public API/Web Admin URL used by RustDesk clients and browsers.
# HTTPS is recommended for external use.
API_SERVER=https://rd.example.com

# Generate with: openssl rand -hex 32
RUSTDESK_API_JWT_KEY=replace-with-random-64-hex-character-secret

# Startup default for forced client login.
# N = disabled, Y = enabled. The Web Admin runtime toggle is not database-persistent.
MUST_LOGIN=N
```

Generate a random secret:

```bash
openssl rand -hex 32
```

Paste the output into:

```env
RUSTDESK_API_JWT_KEY=...
```


If you accept the moving stable tag, change the image to:

```env
RUSTDESK_FULL_S6_IMAGE=ghcr.io/weiyusc/rustdesk-server-full-s6:latest
```

For troubleshooting and production deployments, keep `v0.1.0` or a digest pinned. Use `preview` only for test environments that intentionally follow preview updates.

## 4. Start the stack

```bash
docker compose up -d
```

Check status:

```bash
docker compose ps
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}}'
```

## 5. Get the first admin password

On first boot, the API service normally prints a random admin password in the logs:

```bash
docker logs rustdesk-full-s6 2>&1 | grep -i 'Admin Password' | tail -1
```

If the password is lost, reset it:

```bash
docker exec -w /app rustdesk-full-s6 \
  /app/apimain -c /app/conf/config.yaml reset-admin-pwd '<new-password>'
```

## 6. Verify

```bash
curl -fsS http://127.0.0.1:21114/api/version
curl -fsS http://127.0.0.1:21114/api/build-info
curl -fsSI http://127.0.0.1:21114/_admin/ | head -5
```

If an HTTPS domain is configured, verify it too:

```bash
curl -fsS https://<your-domain>/api/version
curl -fsSI https://<your-domain>/_admin/ | head -5
```

## 7. Upgrade note

Before upgrading, back up:

```text
./data/server
./data/app
```

For detailed upgrade and rollback steps, see:

- [Upgrade and rollback guide](upgrade-rollback.en.md)
- [Full deployment guide](deployment.en.md)

## 8. Parameters and common failure modes

### 8.1 Required parameters

| Parameter | Required | Purpose | If missing or wrong |
| --- | --- | --- | --- |
| `PUBLIC_HOST` | Required | Public host or IP reachable by RustDesk clients. It is used to form ID Server and Relay Server values. | Clients import a configuration that points at the wrong server, devices look offline, or connections go to an old deployment. |
| `API_SERVER` | Required | Full API/Web Admin URL used for account login, WebAuth browser handoff, and browser access. HTTPS is recommended externally. | Client account login or WebAuth fails; a client may look logged in but fail connection authentication. |
| `RUSTDESK_API_JWT_KEY` | Required | Shared secret used by the API to sign login tokens and by `hbbs` to validate them when `MUST_LOGIN` is enabled. Generate with `openssl rand -hex 32`. | With `MUST_LOGIN=Y`, a missing or inconsistent key makes logged-in clients fail with `login-required`; hbbs logs `invalid login token`. Changing it invalidates existing client login tokens, so clients must log in again. |
| `/data/id_ed25519` and `/data/id_ed25519.pub` | Required | RustDesk server private/public key pair. Client `Key` must come from this public key. | Missing, malformed, or mismatched keys cause `invalid public key`, connection failures, or key-exchange failures when encrypted-only mode is enabled. |
| `RELAY` | Required | Relay address returned by hbbs, usually `${PUBLIC_HOST}:21117`. | Relay fallback fails or clients use the wrong relay. |

### 8.2 Optional parameters

| Parameter | Required | Purpose | If missing or wrong |
| --- | --- | --- | --- |
| `MUST_LOGIN` | Optional | Startup default for forced client login: `Y` enables it, `N` disables it. | When enabled, `RUSTDESK_API_JWT_KEY` must be set and clients must log in again. Otherwise connections fail with `login-required`. |
| `ENCRYPTED_ONLY` / `REQUIRE_TCP_KEY_EXCHANGE` | Optional | Require TCP/WS KeyExchange before application messages. | Clients must have the correct server Key. Old clients or wrong keys may be rejected with `Rejecting unencrypted TCP/WS message ... before key exchange`. Start with it disabled until the base stack works. |
| `RUSTDESK_FULL_S6_IMAGE` | Optional | Image tag. Pin a stable tag or digest for production; `latest` is a moving stable tag. | Moving tags can change behavior on upgrade; old tags may miss new fixes and toggles. |
| `RUSTDESK_API_GIN_TRUST_PROXY` | Optional | Trusted reverse proxy address for API/Web Admin, for example `127.0.0.1` when Nginx, BT Panel, or Caddy proxies to the API locally. | If omitted behind a reverse proxy, login logs and device `last_online_ip` show the proxy address, commonly `127.0.0.1`, instead of the real client IP. Do not trust broad ranges when the API port is directly exposed. |
| MySQL `RUSTDESK_API_MYSQL_*` | Optional | Switch the API database to MySQL. | Wrong address, account, TLS, or database name can stop the API from starting. Start with SQLite first unless you need MySQL. |

### 8.3 Server keys and Compose `secrets`

If you use:

```yaml
secrets:
  key_pub:
    file: "secrets/id_ed25519.pub"
  key_priv:
    file: "secrets/id_ed25519"
```

both files must be a valid RustDesk Ed25519 server key pair. Do not replace them with arbitrary text files. The client `Key` is derived from `id_ed25519.pub` and must match the server private key.

One safe creation path is to let the container generate keys in persistent `/data` on first boot, then back them up and reuse them:

```bash
mkdir -p data/server
docker compose up -d
ls -l data/server/id_ed25519 data/server/id_ed25519.pub
```

If you prefer a `secrets/` directory, copy a known-good generated pair into it:

```bash
mkdir -p secrets
cp data/server/id_ed25519 secrets/id_ed25519
cp data/server/id_ed25519.pub secrets/id_ed25519.pub
chmod 600 secrets/id_ed25519
chmod 644 secrets/id_ed25519.pub
```

Never publish the private key. If the server key changes, all clients must update their configured server Key.

## 9. MySQL Compose example

This example matches common control-panel deployments: the full-s6 container uses host networking and connects to a MySQL service on the host at `127.0.0.1:3306`. Replace domains, IPs, passwords, and image tags for your environment.

```yaml
services:
  rustdesk-server:
    container_name: rustdesk-server
    image: ${RUSTDESK_FULL_S6_IMAGE:-ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0}
    network_mode: host
    restart: unless-stopped
    env_file:
      - ".env"
    environment:
      - TZ=Asia/Shanghai
      - MUST_LOGIN=${MUST_LOGIN:-Y}
      - ENCRYPTED_ONLY=${ENCRYPTED_ONLY:-0}
      - RUSTDESK_API_GORM_TYPE=mysql
      - RELAY=${PUBLIC_HOST:?set PUBLIC_HOST}:21117
      - RUSTDESK_API_RUSTDESK_ID_SERVER=${PUBLIC_HOST:?set PUBLIC_HOST}:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=${PUBLIC_HOST:?set PUBLIC_HOST}:21117
      - RUSTDESK_API_RUSTDESK_WS_HOST=${PUBLIC_HOST:?set PUBLIC_HOST}:21119
      - RUSTDESK_API_RUSTDESK_API_SERVER=${API_SERVER:?set API_SERVER}
      - RUSTDESK_API_RUSTDESK_KEY_FILE=/data/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=${RUSTDESK_API_JWT_KEY:?set RUSTDESK_API_JWT_KEY}
    volumes:
      - ./data/server:/data
      - ./data/app:/app/data
```

If you want to import an existing RustDesk server key instead of letting the container generate one in `./data/server`, first make sure `secrets/id_ed25519` and `secrets/id_ed25519.pub` both exist and form a valid pair, then add this to the service:

```yaml
    secrets:
      - key_pub
      - key_priv

secrets:
  key_pub:
    file: "secrets/id_ed25519.pub"
  key_priv:
    file: "secrets/id_ed25519"
```

The full-s6 `key-secret` init step copies these secrets to `/data/id_ed25519.pub` and `/data/id_ed25519` only when `/data` does not already contain keys, then validates the pair. If only one file is present, or the pair is invalid, the container stops.

Matching `.env` example:

```env
# MySQL connection. Replace the password with your own strong secret; do not commit this file.
# You may create the database ahead of time. If the app creates it, use a safe DB name and grant CREATE plus migration/table permissions.
RUSTDESK_API_MYSQL_USERNAME=rustdesk
RUSTDESK_API_MYSQL_PASSWORD=replace-with-strong-password
RUSTDESK_API_MYSQL_ADDR=127.0.0.1:3306
RUSTDESK_API_MYSQL_DBNAME=rustdesk
RUSTDESK_API_MYSQL_TLS=false

# RustDesk host exposed to clients. Do not add a scheme or port to PUBLIC_HOST.
# The Compose file uses PUBLIC_HOST to build RELAY, ID Server, Relay Server, and WS Host.
PUBLIC_HOST=your-server.example.com

# Public API/Web URL. Use HTTPS for production, for example https://rd.example.com.
API_SERVER=https://rd.example.com

# Required shared login-token signing key for API and hbbs.
# Generate with: openssl rand -hex 32
RUSTDESK_API_JWT_KEY=replace-with-random-64-hex-character-secret

# Optional startup defaults.
MUST_LOGIN=Y
ENCRYPTED_ONLY=0

# Optional: set this when API/Web Admin is behind a local reverse proxy such as
# Nginx, BT Panel, or Caddy. It lets the API trust X-Forwarded-For from that
# proxy so login logs and device "last online IP" show the real client IP.
# Do not use a broad value when the API port is directly exposed to untrusted clients.
# RUSTDESK_API_GIN_TRUST_PROXY=127.0.0.1
```

Additional MySQL notes:

- You may create the database first. If the app creates it, `RUSTDESK_API_MYSQL_DBNAME` must use safe characters and the account needs `CREATE`, table, and migration permissions.
- If MySQL is not on the host, set `RUSTDESK_API_MYSQL_ADDR` to an address reachable from the container.
- Keep `RUSTDESK_API_JWT_KEY` stable before enabling `MUST_LOGIN`; changing it invalidates existing client login sessions.
- Start with `ENCRYPTED_ONLY=0`; after account login, WebAuth, client import, and connections are verified, consider enabling encrypted-only mode.
