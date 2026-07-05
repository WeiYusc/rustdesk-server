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
    image: ${RUSTDESK_FULL_S6_IMAGE:-ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0-preview.1}
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
# Do not use latest; prefer an explicit preview tag or digest. Use :preview only if you want to follow the newest preview.
RUSTDESK_FULL_S6_IMAGE=ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0-preview.1

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


If you intentionally want to follow the newest preview, change the image to:

```env
RUSTDESK_FULL_S6_IMAGE=ghcr.io/weiyusc/rustdesk-server-full-s6:preview
```

For troubleshooting and production-like trials, keep `v0.1.0-preview.1` or a digest pinned.

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

## 8. Notes

- Do not use `latest`. Pin an explicit image tag or digest for reproducibility; use `preview` only when you intentionally follow preview updates.
- `.env` may contain real secrets. Do not publish it.
- `MUST_LOGIN` is the startup default. The Web Admin runtime toggle is not database-persistent.
- HTTPS is recommended for external use.
