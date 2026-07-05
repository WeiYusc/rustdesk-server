# RustDesk full-s6 Upgrade and Rollback Guide

This guide is for operators who already have a `rustdesk-full-s6` container running and want to upgrade the image while preserving data and keeping a rollback path.

Core rule: **back up first, replace second, verify last**.

> Before upgrading, make sure you know the current image, mounted data paths, and environment variables. Do not paste full environment dumps containing passwords, tokens, or secrets into public documents or issue reports.

## 1. Data that must be preserved

Preserve these directories during upgrades:

| Container path | Recommended host path | Content |
| --- | --- | --- |
| `/data` | `/opt/rustdesk-full-s6/server-data` | Server keys such as `id_ed25519` and `id_ed25519.pub` |
| `/app/data` | `/opt/rustdesk-full-s6/app-data` | API database, uploaded files, and runtime data |

If `/data` is lost, clients may fail with key mismatch or connection errors. If `/app/data` is lost, accounts, Web Admin data, and uploads may be lost.

## 2. Pre-upgrade audit

Create a restricted audit directory so environment values and logs are not readable by other users:

```bash
stamp=$(date -u +%Y%m%d%H%M%S)
audit_dir=/root/rustdesk-full-s6-upgrade-$stamp
umask 077
mkdir -p "$audit_dir"
```

Save the current state. Note that `docker inspect` may contain environment secrets, and logs may contain the first-run random admin password. Do not publish the audit directory.

```bash
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
  | tee "$audit_dir/docker-ps.before.txt"

docker inspect rustdesk-full-s6 > "$audit_dir/rustdesk-full-s6.before.inspect.json"
docker logs --tail=300 rustdesk-full-s6 > "$audit_dir/rustdesk-full-s6.before.logs.txt" 2>&1 || true
ss -lntup | grep -E ':2111[4-9]' | tee "$audit_dir/ports.before.txt" || true
ss -lnuap | grep ':21116' | tee -a "$audit_dir/ports.before.txt" || true
```

Save the environment list separately and keep it private:

```bash
docker inspect rustdesk-full-s6 \
  --format '{{range .Config.Env}}{{println .}}{{end}}' \
  > "$audit_dir/env.list"
chmod 600 "$audit_dir"/*
```

## 3. Back up data directories

Container rollback restores the old program, but it does not automatically undo database or data-directory changes already written by the new program. Before replacing the container, back up the host directories mounted as `/data` and `/app/data`.

To avoid copying the database or uploads while they are being written, schedule a short maintenance window and stop the container before archiving the data directories:

```bash
docker stop rustdesk-full-s6
```

If you use the recommended paths from this guide, run:

```bash
tar -C /opt -czf "$audit_dir/server-data.before.tgz" rustdesk-full-s6/server-data
tar -C /opt -czf "$audit_dir/app-data.before.tgz" rustdesk-full-s6/app-data
chmod 600 "$audit_dir"/*.tgz
```

If your deployment uses different mount paths, follow the `Mounts` section from `docker inspect rustdesk-full-s6` and back up the actual host directories.

If you still need to pull the image or inspect the digest before replacement, you may temporarily restore the old service after the backup finishes:

```bash
docker start rustdesk-full-s6
```

The replacement step below will stop and rename the old container again.

Data restore example, only when you have confirmed that data restore is needed:

```bash
docker stop rustdesk-full-s6
rm -rf /opt/rustdesk-full-s6/server-data /opt/rustdesk-full-s6/app-data
tar -C /opt -xzf "$audit_dir/server-data.before.tgz"
tar -C /opt -xzf "$audit_dir/app-data.before.tgz"
docker start rustdesk-full-s6
```

## 4. Pull and inspect the new image

```bash
new_image=ghcr.io/weiyusc/rustdesk-server-full-s6:<new-tag>
docker pull "$new_image"
docker image inspect "$new_image" \
  --format 'repo={{index .RepoDigests 0}} id={{.Id}} created={{.Created}} size={{.Size}}'
```

If the release notes provide a digest, confirm that the `RepoDigests` value matches it.

## 5. Replace the container

Disable automatic restart first so the old and new containers do not fight for the same ports:

```bash
docker update --restart=no rustdesk-full-s6
```

Rename the old container as the rollback container:

```bash
rollback=rustdesk-full-s6-before-$stamp
docker stop rustdesk-full-s6
docker rename rustdesk-full-s6 "$rollback"
```

Start the new container with the same data directories and environment values. The example below uses the recommended host paths; if your existing deployment uses different paths, follow `docker inspect` instead.

```bash
docker run -d \
  --name rustdesk-full-s6 \
  --restart unless-stopped \
  --env-file "$audit_dir/env.list" \
  -p 21114:21114/tcp \
  -p 21115:21115/tcp \
  -p 21116:21116/tcp \
  -p 21116:21116/udp \
  -p 21117:21117/tcp \
  -p 21118:21118/tcp \
  -p 21119:21119/tcp \
  -v /opt/rustdesk-full-s6/server-data:/data \
  -v /opt/rustdesk-full-s6/app-data:/app/data \
  "$new_image"
```

## 6. Wait for health

```bash
for i in $(seq 1 120); do
  health=$(docker inspect -f '{{.State.Health.Status}}' rustdesk-full-s6 2>/dev/null || true)
  [ "$health" = healthy ] && break
  sleep 1
done

docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'
```

If the container is not `healthy`, do not clean up the old container. Inspect logs and prepare to roll back.

## 7. Post-upgrade checks

```bash
curl -fsS http://127.0.0.1:21114/api/version
curl -fsS http://127.0.0.1:21114/api/build-info
curl -fsSI http://127.0.0.1:21114/_admin/ | head -5
ss -lntup | grep -E ':2111[4-9]'
ss -lnuap | grep ':21116'
docker logs --since=10m rustdesk-full-s6 2>&1 \
  | grep -Ei 'panic|fatal|traceback|migration failed|error' \
  | tail -30 || true
```

If the Web Admin is exposed through an HTTPS domain, check that domain too:

```bash
curl -fsS https://<your-domain>/api/version
curl -fsSI https://<your-domain>/_admin/ | head -5
```

## 8. Rollback

If the new container fails to start or validation fails, roll the container back first:

```bash
docker rm -f rustdesk-full-s6 || true
docker rename "$rollback" rustdesk-full-s6
docker update --restart unless-stopped rustdesk-full-s6
docker start rustdesk-full-s6
```

Verify after container rollback:

```bash
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'
curl -fsS http://127.0.0.1:21114/api/version
```

If the new version has already modified the database or other files under `/app/data`, container rollback may not be enough. Restore data from the pre-upgrade backup from section 3 when needed.

## 9. Cleanup policy

After the new version is stable, clean up old assets conservatively:

- keep the latest 1 or 2 rollback containers;
- remove uploaded tarballs that have already been loaded into Docker;
- remove old images that are not referenced by kept containers;
- do not remove independent validation containers, such as database migration or MySQL validation containers, unless you know they are no longer needed.

Inspect containers and images:

```bash
docker ps -a --format 'table {{.Names}}	{{.Image}}	{{.Status}}'
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' \
  | grep -Ei 'rustdesk|REPOSITORY' || true
```

Example old rollback removal:

```bash
docker rm rustdesk-full-s6-before-<old-stamp>
```

Before removing any image, confirm that no kept container still references it.

## 10. Notes

- Do not delete `/data` or `/app/data` during upgrades.
- Do not upload `env.list` files containing real secrets to public repositories.
- If `MUST_LOGIN` is enabled, confirm the runtime state after upgrade. A container restart returns it to the environment-variable default.
- If the server Key changes, existing clients may need to re-import configuration.
- Rollback containers are short-term safety assets; do not keep them indefinitely.
