# RustDesk full-s6 升级与回滚指南

本文面向已经运行 `rustdesk-full-s6` 容器的运维人员，目标是在保留数据的前提下升级镜像，并在失败时能快速回滚。

核心原则：**先备份、再替换、最后验证**。

> 升级前请确认你知道当前容器使用的镜像、挂载目录和环境变量。不要在公开文档或工单中粘贴包含密码、令牌或密钥的完整环境变量。

## 1. 哪些数据必须保留

升级时必须保留以下目录：

| 容器路径 | 推荐宿主机路径 | 内容 |
| --- | --- | --- |
| `/data` | `/opt/rustdesk-full-s6/server-data` | 服务端密钥，包括 `id_ed25519` 和 `id_ed25519.pub` |
| `/app/data` | `/opt/rustdesk-full-s6/app-data` | 接口服务数据库、上传文件和运行数据 |

如果 `/data` 丢失，客户端可能出现 Key 不匹配或连接失败。如果 `/app/data` 丢失，账号、管理后台数据和上传文件可能丢失。

## 2. 升级前检查

创建权限受限的审计目录，避免环境变量和日志被其他用户读取：

```bash
stamp=$(date -u +%Y%m%d%H%M%S)
audit_dir=/root/rustdesk-full-s6-upgrade-$stamp
umask 077
mkdir -p "$audit_dir"
```

保存当前状态。注意：`docker inspect` 可能包含环境变量，日志可能包含首次启动时的随机管理员密码，因此审计目录不要公开上传。

```bash
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
  | tee "$audit_dir/docker-ps.before.txt"

docker inspect rustdesk-full-s6 > "$audit_dir/rustdesk-full-s6.before.inspect.json"
docker logs --tail=300 rustdesk-full-s6 > "$audit_dir/rustdesk-full-s6.before.logs.txt" 2>&1 || true
ss -lntup | grep -E ':2111[4-9]' | tee "$audit_dir/ports.before.txt" || true
ss -lnuap | grep ':21116' | tee -a "$audit_dir/ports.before.txt" || true
```

单独保存环境变量清单，注意不要公开：

```bash
docker inspect rustdesk-full-s6 \
  --format '{{range .Config.Env}}{{println .}}{{end}}' \
  > "$audit_dir/env.list"
chmod 600 "$audit_dir"/*
```

## 3. 备份数据目录

容器回滚只能恢复旧程序，不能自动撤销新程序已经写入数据库或数据目录的变化。因此替换容器前，请先备份 `/data` 和 `/app/data` 对应的宿主机目录。

为避免数据库或上传文件在备份过程中被写入，建议安排短维护窗口，先停止容器再打包数据目录：

```bash
docker stop rustdesk-full-s6
```

如果你使用本指南推荐的目录，可以执行：

```bash
tar -C /opt -czf "$audit_dir/server-data.before.tgz" rustdesk-full-s6/server-data
tar -C /opt -czf "$audit_dir/app-data.before.tgz" rustdesk-full-s6/app-data
chmod 600 "$audit_dir"/*.tgz
```

如果你的挂载目录不同，请以 `docker inspect rustdesk-full-s6` 中的 `Mounts` 为准，备份实际宿主机目录。

如果你还需要先拉取镜像或检查摘要，可以在备份完成后临时恢复旧容器服务：

```bash
docker start rustdesk-full-s6
```

后续替换容器时仍会再次停止并重命名旧容器。

恢复数据示例（仅在确认需要恢复数据时执行）：

```bash
docker stop rustdesk-full-s6
rm -rf /opt/rustdesk-full-s6/server-data /opt/rustdesk-full-s6/app-data
tar -C /opt -xzf "$audit_dir/server-data.before.tgz"
tar -C /opt -xzf "$audit_dir/app-data.before.tgz"
docker start rustdesk-full-s6
```

## 4. 拉取并确认新镜像

```bash
new_image=ghcr.io/weiyusc/rustdesk-server-full-s6:<new-tag>
docker pull "$new_image"
docker image inspect "$new_image" \
  --format 'repo={{index .RepoDigests 0}} id={{.Id}} created={{.Created}} size={{.Size}}'
```

如果发布说明提供了摘要值，请确认 `RepoDigests` 中的摘要一致。

## 5. 替换容器

先停止自动重启，避免新旧容器争抢端口：

```bash
docker update --restart=no rustdesk-full-s6
```

把旧容器改名为回滚容器：

```bash
rollback=rustdesk-full-s6-before-$stamp
docker stop rustdesk-full-s6
docker rename rustdesk-full-s6 "$rollback"
```

使用与旧容器相同的数据目录和环境变量启动新容器。下面示例使用固定目录；如果你的旧容器路径不同，请以 `docker inspect` 为准。

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

## 6. 等待健康状态

```bash
for i in $(seq 1 120); do
  health=$(docker inspect -f '{{.State.Health.Status}}' rustdesk-full-s6 2>/dev/null || true)
  [ "$health" = healthy ] && break
  sleep 1
done

docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'
```

如果健康状态不是 `healthy`，不要继续清理旧容器，先查看日志并准备回滚。

## 7. 升级后验证

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

如果通过 HTTPS 域名访问管理后台，也要验证域名：

```bash
curl -fsS https://<your-domain>/api/version
curl -fsSI https://<your-domain>/_admin/ | head -5
```

## 8. 回滚

如果新容器启动失败或验证不通过，先回滚容器：

```bash
docker rm -f rustdesk-full-s6 || true
docker rename "$rollback" rustdesk-full-s6
docker update --restart unless-stopped rustdesk-full-s6
docker start rustdesk-full-s6
```

容器回滚后再次验证：

```bash
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'
curl -fsS http://127.0.0.1:21114/api/version
```

如果新版本已经修改 `/app/data` 中的数据库或其他数据，单纯回滚容器可能不够，还需要按第 3 节从升级前备份恢复数据。

## 9. 清理策略

确认新版本稳定后，可以清理旧资产：

- 保留最近 1 到 2 个回滚容器；
- 删除已经加载进 Docker 的上传包；
- 删除不再被任何保留容器引用的旧镜像；
- 不要删除独立验证容器，例如数据库迁移或 MySQL 验证容器，除非你明确知道它们已经无用。

查看容器和镜像：

```bash
docker ps -a --format 'table {{.Names}}	{{.Image}}	{{.Status}}'
docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' \
  | grep -Ei 'rustdesk|REPOSITORY' || true
```

删除旧回滚容器示例：

```bash
docker rm rustdesk-full-s6-before-<old-stamp>
```

删除旧镜像前，请确认没有保留容器仍在引用该镜像。

## 10. 注意事项

- 升级过程中不要删除 `/data` 和 `/app/data`。
- 不要把包含真实密钥的 `env.list` 上传到公开仓库。
- 如果启用了 `MUST_LOGIN`，升级后要确认运行时状态是否符合预期。容器重启会回到环境变量默认值。
- 如果更换了服务端 Key，旧客户端可能需要重新导入配置。
- 回滚容器只是短期保险，不应无限保留。
