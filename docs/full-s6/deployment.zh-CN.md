# RustDesk full-s6 集成镜像部署指南

本文面向第一次部署 `rustdesk-server-full-s6` 集成镜像的运维人员。集成镜像把以下组件放在同一个容器中，由 s6 统一管理：

- `hbbs`：标识服务器，用于设备发现和连接协商。
- `hbbr`：中继服务器，用于无法直连时的数据转发。
- `rustdesk-api`：账号、地址簿、审计和管理接口。
- Web Admin：管理后台静态资源。

> 示例中的域名、地址、密钥和镜像标签都需要替换为你的部署值。不要把真实密码、令牌、私钥、JWT 密钥或未打码截图提交到公开仓库。

## 1. 适用范围

本指南适用于单机 Docker 部署：

- 一个容器同时运行标识服务器、中继服务器、接口服务和管理后台；
- 数据通过宿主机目录持久化；
- 管理后台建议通过 HTTPS 域名访问；
- 当前文档以 `linux/amd64` 镜像为主。

如果你只想分别运行官方 `hbbs` / `hbbr`，请参考 RustDesk 官方自托管文档。

## 2. 部署前准备

### 2.1 端口

需要放行以下端口：

| 端口 | 协议 | 用途 |
| --- | --- | --- |
| `21114` | TCP | 接口服务与管理后台 |
| `21115` | TCP | RustDesk 服务端辅助端口 |
| `21116` | TCP/UDP | 标识服务器 `hbbs` |
| `21117` | TCP | 中继服务器 `hbbr` |
| `21118` | TCP | Web 客户端相关端口，按需使用 |
| `21119` | TCP | Web 客户端相关端口，按需使用 |

### 2.2 数据目录

建议使用固定目录，便于备份和升级：

```text
/opt/rustdesk-full-s6/server-data  -> /data
/opt/rustdesk-full-s6/app-data     -> /app/data
```

目录用途：

- `/data`：保存服务端密钥，例如 `id_ed25519` 和 `id_ed25519.pub`。
- `/app/data`：保存接口服务数据库、上传文件和运行数据。

> 不要在升级时删除这两个目录，否则可能导致客户端密钥不匹配、账号数据丢失或管理后台数据丢失。

### 2.3 准备随机密钥

`RUSTDESK_API_JWT_KEY` 用于签发和校验登录令牌。下面命令会生成 32 字节随机值，并以 64 个十六进制字符显示：

```bash
openssl rand -hex 32
```

请妥善保存，不要写入公开文档、截图或工单。


## 镜像标签选择

- `v0.1.0-preview.1`：固定预览版本，适合可复现部署、排障和回滚。
- `preview`：浮动标签，指向最新预览版，适合愿意跟随预览更新的测试环境。
- `latest`：暂不发布，避免把预览版误认为稳定版。

## 3. 启动容器

如果你希望复制 `docker-compose.yml` 和 `.env` 模板，优先查看 [Docker Compose 模板](compose.zh-CN.md)。下面的 `docker run` 示例适合手动部署或理解每个参数的作用。

请把 `<your-host-or-ip>`、`<your-domain>`、`<random-64-hex-character-secret>` 和 `<tag>` 替换为你的值。

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

如果暂时没有 HTTPS 域名，也可以先用 `http://<your-host-or-ip>:21114` 验证。但对外使用时建议配置 HTTPS 反向代理。

## 4. 常用环境变量

| 变量 | 说明 | 示例 |
| --- | --- | --- |
| `RELAY` | `hbbs` 返回给客户端的中继服务器地址 | `<your-host-or-ip>:21117` |
| `RUSTDESK_API_RUSTDESK_ID_SERVER` | 管理后台展示给客户端的标识服务器地址 | `<your-host-or-ip>:21116` |
| `RUSTDESK_API_RUSTDESK_RELAY_SERVER` | 管理后台展示给客户端的中继服务器地址 | `<your-host-or-ip>:21117` |
| `RUSTDESK_API_RUSTDESK_API_SERVER` | 客户端账号登录和 Web 授权使用的接口服务地址 | `https://<your-domain>` |
| `RUSTDESK_API_RUSTDESK_KEY_FILE` | 服务端公钥文件路径 | `/data/id_ed25519.pub` |
| `RUSTDESK_API_JWT_KEY` | 登录令牌签名密钥 | 使用随机值 |
| `MUST_LOGIN` | 容器启动时的强制登录默认值 | `Y` 或 `N` |

说明：

- `MUST_LOGIN` 是启动默认值。管理后台里的“要求客户端登录”会通过 `hbbs` 运行时命令即时生效；容器或 `hbbs` 重启后，会回到环境变量的默认值。
- 邮件、数据库等更多接口服务变量请参考 `rustdesk-api` 文档。首次部署建议先使用默认 SQLite，确认基础链路可用后再切换数据库。

## 5. 首次登录与密码重置

首次启动时，接口服务日志通常会打印随机管理员密码。请只在安全终端中查看，不要截图公开传播。

```bash
docker logs rustdesk-full-s6 2>&1 | grep -i 'Admin Password' | tail -1
```

如果忘记管理员密码，可以在容器内重置：

```bash
docker exec -w /app rustdesk-full-s6 \
  /app/apimain -c /app/conf/config.yaml reset-admin-pwd '<new-password>'
```

重置后请使用新的强密码登录管理后台。

## 6. 客户端配置

登录管理后台后，进入“个人信息 / 服务器连接凭据”，复制客户端导入配置。客户端至少需要确认：

- 标识服务器地址正确；
- 中继服务器地址正确；
- 接口服务地址正确；
- Key 与服务端公钥匹配；
- 启用强制登录前，客户端已经能完成账号登录。

客户端登录、强制登录和常见错误矩阵，请参考 API-Web 文档：

- [客户端登录、MUST_LOGIN 与服务器配置排障指南](https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.zh-CN.md)

## 7. 部署后验证

### 7.1 容器健康状态

```bash
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}}'
```

期望看到：

```text
status=running health=healthy
```

### 7.2 接口服务

```bash
curl -fsS http://127.0.0.1:21114/api/version
curl -fsS http://127.0.0.1:21114/api/build-info
```

`/api/build-info` 会返回镜像内包含的服务端、接口服务和管理前端版本指纹。

### 7.3 管理后台

```bash
curl -fsSI http://127.0.0.1:21114/_admin/ | head -5
```

如果已经配置 HTTPS 域名，也要验证：

```bash
curl -fsSI https://<your-domain>/_admin/ | head -5
```

### 7.4 端口监听

```bash
ss -lntup | grep -E ':2111[4-9]'
ss -lnuap | grep ':21116'
```

## 8. 安全建议

- 对外使用时建议配置 HTTPS。
- 不要公开真实域名、IP、Key、令牌、管理员密码或未打码截图。
- 防火墙只开放必要端口。
- 升级前请按[升级与回滚指南](upgrade-rollback.zh-CN.md)备份 `/data` 和 `/app/data`。
- 如果启用 `MUST_LOGIN=Y`，请先用已登录客户端和未登录客户端分别验证行为。
- 当前集成镜像仍按 s6 模式以 root 作为容器内启动用户运行，非 root 运行属于后续加固事项。

## 9. 已知边界

- 当前预览镜像主要验证 `linux/amd64`。
- 当前文档不发布或推荐 `latest` 标签。
- 强制登录的运行时开关不会写入数据库，重启后以环境变量为准。
- 真实客户端连接结果会受客户端版本、网络和服务器配置影响。
