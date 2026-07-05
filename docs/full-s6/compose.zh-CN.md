# RustDesk full-s6 Docker Compose 模板

本文面向希望用 Docker Compose 部署 `rustdesk-server-full-s6` 的运维人员。相比一长串 `docker run`，Compose 模板更方便复制、保存和升级。

> 示例中的域名、地址和密钥都必须替换为你的值。不要把真实 `.env` 文件提交到公开仓库。

## 1. 准备目录

```bash
mkdir -p rustdesk-full-s6/data/server rustdesk-full-s6/data/app
cd rustdesk-full-s6
```

目录用途：

- `./data/server`：保存服务端密钥，对应容器内 `/data`。
- `./data/app`：保存接口服务数据库、上传文件和运行数据，对应容器内 `/app/data`。

## 2. 复制 `docker-compose.yml`

把下面内容保存为：

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

## 3. 复制 `.env` 模板

把下面内容保存为：

```text
.env
```

然后修改 `PUBLIC_HOST`、`API_SERVER` 和 `RUSTDESK_API_JWT_KEY`。如果保留模板里的占位域名，容器可能可以启动，但客户端无法正确连接到你的服务器。

```env
# RustDesk full-s6 集成镜像。
# 不要使用 latest；请固定明确的预览标签或摘要。
RUSTDESK_FULL_S6_IMAGE=ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0-preview.1

# 客户端可以访问的公网域名或 IP，用于标识服务器和中继服务器。
# 这里不要填写 http://、https:// 或端口。
PUBLIC_HOST=your-server.example.com

# 客户端账号登录和浏览器访问管理后台使用的接口服务地址。
# 对外使用建议配置 HTTPS。
API_SERVER=https://rd.example.com

# 生成命令：openssl rand -hex 32
RUSTDESK_API_JWT_KEY=replace-with-random-64-hex-character-secret

# 强制客户端登录的启动默认值。
# N = 不启用，Y = 启用。管理后台的运行时开关不会写入数据库。
MUST_LOGIN=N
```

生成随机密钥：

```bash
openssl rand -hex 32
```

把输出填入：

```env
RUSTDESK_API_JWT_KEY=...
```

## 4. 启动

```bash
docker compose up -d
```

查看状态：

```bash
docker compose ps
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}}'
```

## 5. 获取首次管理员密码

首次启动时，接口服务日志通常会打印随机管理员密码：

```bash
docker logs rustdesk-full-s6 2>&1 | grep -i 'Admin Password' | tail -1
```

如果忘记密码，可以重置：

```bash
docker exec -w /app rustdesk-full-s6 \
  /app/apimain -c /app/conf/config.yaml reset-admin-pwd '<new-password>'
```

## 6. 验证

```bash
curl -fsS http://127.0.0.1:21114/api/version
curl -fsS http://127.0.0.1:21114/api/build-info
curl -fsSI http://127.0.0.1:21114/_admin/ | head -5
```

如果配置了 HTTPS 域名，也要验证：

```bash
curl -fsS https://<your-domain>/api/version
curl -fsSI https://<your-domain>/_admin/ | head -5
```

## 7. 升级提示

升级前请先备份：

```text
./data/server
./data/app
```

更详细的升级和回滚步骤见：

- [升级与回滚指南](upgrade-rollback.zh-CN.md)
- [完整部署指南](deployment.zh-CN.md)

## 8. 注意事项

- 不要使用 `latest`，请固定镜像标签或摘要。
- `.env` 可能包含真实密钥，不要公开。
- `MUST_LOGIN` 是启动默认值；管理后台运行时开关不会写入数据库。
- 对外使用时建议配置 HTTPS。
