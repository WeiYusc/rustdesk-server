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

## 3. 复制 `.env` 模板

把下面内容保存为：

```text
.env
```

然后修改 `PUBLIC_HOST`、`API_SERVER` 和 `RUSTDESK_API_JWT_KEY`。如果保留模板里的占位域名，容器可能可以启动，但客户端无法正确连接到你的服务器。

```env
# RustDesk full-s6 集成镜像。
# 建议固定明确的稳定标签或摘要。latest 会跟随最新稳定版移动；preview 保留给预览测试。
RUSTDESK_FULL_S6_IMAGE=ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0

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


如果你接受稳定版浮动标签，可以把镜像改成：

```env
RUSTDESK_FULL_S6_IMAGE=ghcr.io/weiyusc/rustdesk-server-full-s6:latest
```

排障和生产环境仍建议固定 `v0.1.0` 或摘要。`preview` 只建议用于愿意跟随预览更新的测试环境。

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

## 8. 参数说明与常见后果

### 8.1 必要参数

| 参数 | 是否必要 | 说明 | 配错或缺失的后果 |
| --- | --- | --- | --- |
| `PUBLIC_HOST` | 必要 | 客户端可访问的公网域名或 IP，不带协议和端口。Compose 会用它生成 ID Server、Relay Server。 | 客户端导入配置指向错误服务器，设备离线、连接失败或连到旧服务。 |
| `API_SERVER` | 必要 | 客户端账号登录、WebAuth 跳转和浏览器访问管理后台使用的完整 URL。对外建议 HTTPS。 | 客户端账号登录失败、WebAuth 回调失败、已登录但连接时仍像未登录。 |
| `RUSTDESK_API_JWT_KEY` | 必要 | API 签发登录 token、hbbs 在 `MUST_LOGIN` 下校验 token 的共享密钥。使用 `openssl rand -hex 32` 生成。 | 如果启用 `MUST_LOGIN=Y` 但缺失或 API/hbbs 不一致，客户端即使账号密码或 WebAuth 登录成功，连接时仍会报 `login-required`，hbbs 日志出现 `invalid login token`。修改后旧登录 token 会失效，客户端需要重新登录。 |
| `/data/id_ed25519` 与 `/data/id_ed25519.pub` | 必要 | RustDesk 服务端私钥和公钥。客户端配置里的 Key 必须来自这份公钥。 | Key 缺失、格式错误或客户端使用了别的服务器 Key 时，会出现 `invalid public key`、连接失败或强制加密场景下无法完成握手。 |
| `RELAY` | 必要 | hbbs 返回给客户端的 relay 地址，通常是 `${PUBLIC_HOST}:21117`。 | 直连失败时无法正确回落到中继，或者客户端连到错误 relay。 |

### 8.2 可选参数

| 参数 | 是否必要 | 说明 | 配错或缺失的后果 |
| --- | --- | --- | --- |
| `MUST_LOGIN` | 可选 | 启动时强制客户端登录的默认值，`Y` 开启，`N` 关闭。 | 开启后必须配置 `RUSTDESK_API_JWT_KEY`，并要求客户端重新登录；否则连接报 `login-required`。关闭后未登录客户端也可按普通 RustDesk 行为尝试连接。 |
| `ENCRYPTED_ONLY` / `REQUIRE_TCP_KEY_EXCHANGE` | 可选 | 强制 TCP/WS 在应用消息前完成 KeyExchange。 | 开启后客户端必须配置正确 Key；旧客户端或 Key 错误会被拒绝，日志可能出现 `Rejecting unencrypted TCP/WS message ... before key exchange`。首次部署建议先关闭，基础链路跑通后再启用。 |
| `RUSTDESK_FULL_S6_IMAGE` | 可选 | 镜像标签。建议生产固定稳定标签或 digest；`latest` 是稳定版浮动标签。 | 使用浮动标签可能在升级时引入新行为；使用过旧标签可能缺少新开关或修复。 |
| `RUSTDESK_API_GIN_TRUST_PROXY` | 可选 | 当 API/Web 管理后台放在 Nginx、宝塔、Caddy 等反向代理后面时，填写可信反代地址，例如 `127.0.0.1`。 | 未配置时，登录日志和设备管理“最后在线 IP”会显示反代地址（常见为 `127.0.0.1`），而不是真实客户端公网 IP。不要在 API 直接暴露到公网时盲目信任所有来源。 |
| MySQL 相关 `RUSTDESK_API_MYSQL_*` | 可选 | 切换 API 数据库到 MySQL。 | 数据库地址、账号、TLS 或库名错误会导致 API 启动失败；建议先用 SQLite 跑通基础链路，再切 MySQL。 |

### 8.3 服务端密钥和 Compose `secrets`

如果使用：

```yaml
secrets:
  key_pub:
    file: "secrets/id_ed25519.pub"
  key_priv:
    file: "secrets/id_ed25519"
```

这两个文件必须是真正的 RustDesk 服务端 Ed25519 密钥，不能用随便生成的文本文件替代。客户端导入配置中的 `Key` 来自 `id_ed25519.pub`，必须与服务端实际私钥配对。

推荐创建方式之一：先让容器用持久化 `/data` 首次启动，由 `hbbs` 自动生成密钥，然后备份并复用：

```bash
mkdir -p data/server
docker compose up -d
ls -l data/server/id_ed25519 data/server/id_ed25519.pub
```

如果你选择使用 `secrets/` 目录，请把已生成并验证可用的密钥复制进去：

```bash
mkdir -p secrets
cp data/server/id_ed25519 secrets/id_ed25519
cp data/server/id_ed25519.pub secrets/id_ed25519.pub
chmod 600 secrets/id_ed25519
chmod 644 secrets/id_ed25519.pub
```

不要公开私钥；更换服务端密钥后，所有客户端都需要更新服务器 Key。

## 9. MySQL Compose 示例

下面示例接近宝塔/面板常见编排：RustDesk full-s6 容器使用 host 网络，MySQL 在宿主机 `127.0.0.1:3306` 或同机数据库服务上运行。请按你的环境替换域名、IP、数据库密码和镜像标签。

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

如果你要导入已有 RustDesk 服务端密钥，而不是让容器在 `./data/server` 中自动生成，可以在确认 `secrets/id_ed25519` 和 `secrets/id_ed25519.pub` 都存在且配对后，再给服务追加：

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

full-s6 的 `key-secret` 初始化步骤会在 `/data` 缺少密钥时把这两个 secret 复制到 `/data/id_ed25519.pub` 和 `/data/id_ed25519`，并校验密钥对是否有效；如果只提供其中一个，或密钥不配对，容器会停止。

配套 `.env` 示例：

```env
# MySQL 连接。密码必须换成你自己的强密码，不要提交到仓库。
# 数据库可提前创建；如果依赖程序自动创建，库名必须使用安全字符，且账号需要 CREATE 和迁移权限。
RUSTDESK_API_MYSQL_USERNAME=rustdesk
RUSTDESK_API_MYSQL_PASSWORD=replace-with-strong-password
RUSTDESK_API_MYSQL_ADDR=127.0.0.1:3306
RUSTDESK_API_MYSQL_DBNAME=rustdesk
RUSTDESK_API_MYSQL_TLS=false

# 对客户端暴露的 RustDesk 服务地址。不要给 PUBLIC_HOST 加协议或端口。
# Compose 文件会用 PUBLIC_HOST 生成 RELAY、ID Server、Relay Server 和 WS Host。
PUBLIC_HOST=your-server.example.com

# API/Web 公开地址。生产建议使用 HTTPS，例如 https://rd.example.com。
API_SERVER=https://rd.example.com

# 必填：API 与 hbbs 共享的登录 token 签名密钥。
# 生成：openssl rand -hex 32
RUSTDESK_API_JWT_KEY=replace-with-random-64-hex-character-secret

# 可选：启动默认值。
MUST_LOGIN=Y
ENCRYPTED_ONLY=0

# 可选：当 API/Web 管理后台经过本机 Nginx、宝塔、Caddy 等反代时设置。
# 这会让 API 信任该反代传入的 X-Forwarded-For，使登录日志和设备“最后在线 IP”
# 显示真实客户端公网 IP。API 端口若直接暴露给不可信客户端，不要配置过宽的信任范围。
# RUSTDESK_API_GIN_TRUST_PROXY=127.0.0.1
```

MySQL 方案的额外注意事项：

- 数据库可以提前创建；如果依赖程序自动创建，`RUSTDESK_API_MYSQL_DBNAME` 只能使用安全字符，且账号需要 `CREATE`、建表和迁移权限。
- 如果 MySQL 不在宿主机本地，请把 `RUSTDESK_API_MYSQL_ADDR` 改成容器可访问的地址。
- `RUSTDESK_API_JWT_KEY` 必须从第一次启用 `MUST_LOGIN` 前就固定下来；后续更换会让旧客户端登录态失效。
- 首次部署建议先用 `ENCRYPTED_ONLY=0`，确认账号登录、WebAuth、客户端导入配置和连接都正常后，再考虑开启强制加密。
