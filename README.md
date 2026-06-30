# RustDesk Server / RustDesk 服务端

[中文](#中文) · [English](#english)

## 中文

这是 `WeiYusc/rustdesk-server` 下游 fork，基于官方 `rustdesk/rustdesk-server`，用于自托管 RustDesk ID/中继服务，并与配套的 `WeiYusc/rustdesk-api` 和 `WeiYusc/rustdesk-api-web` 组合成完整的 Web 管理/API/服务端栈。

### 当前能力

- `hbbs`：RustDesk ID/Rendezvous 服务。
- `hbbr`：RustDesk Relay 中继服务。
- `rustdesk-utils`：RustDesk 服务端工具。
- 反向代理头安全边界：默认只信任 loopback 代理的 `X-Real-IP` / `X-Forwarded-For`；非 loopback 可信代理需显式启用 `TRUST_PROXY_HEADERS=1`。
- 本仓库保留官方二进制/compose 部署路径，并新增 full-s6 集成镜像构建脚本。

### 与 API / Web 前端的关系

完整管理栈由三个仓库组成：

| 仓库 | 作用 |
| --- | --- |
| `WeiYusc/rustdesk-server` | `hbbs` / `hbbr` 服务端与 full-s6 集成镜像构建入口 |
| `WeiYusc/rustdesk-api` | RustDesk API、账号、地址簿、审计、管理接口 |
| `WeiYusc/rustdesk-api-web` | Vue/Naive UI Web Admin 前端，构建后注入 API 静态资源 |

### 构建

```bash
cargo build --release
```

生成文件位于 `target/release/`：

- `hbbs`
- `hbbr`
- `rustdesk-utils`

### 基础部署方案

生产部署可以继续使用官方文档中的 OSS 自托管方式，分别运行 `hbbs` 与 `hbbr`，并持久化服务端密钥目录。

参考：<https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/>

### full-s6 集成镜像（保留方案）

本仓库已有本地 full-s6 集成镜像构建路径，用于把以下组件放入单个 Docker 镜像：

- `hbbs`
- `hbbr`
- `rustdesk-api`
- 构建后的 `rustdesk-api-web` Web Admin 静态资源

当前状态：

- 本地构建与 smoke 已验证。
- 镜像标签仍是本地标签，例如 `rustdesk-server-full-s6:local`。
- **尚未发布 Docker Hub/GHCR 公共镜像。**
- 公开镜像、tag 策略、升级/回滚说明完成前，请把该方式视为“保留方案”。

详见：[docker/full-s6/README.md](docker/full-s6/README.md)。

### 验证边界

已验证：

- 本地构建。
- Compose/binary 基线。
- full-s6 镜像本地启动、Web Admin/API/server 进程、管理员登录与配置接口。
- WebSocket 端口基础升级检查。

仍需后续验证：

- 真实两台/两个身份 RustDesk 客户端强制登录与连接链路。
- 公共镜像发布、长期升级和回滚流程。
- 多架构镜像与非 linux/amd64 平台。

### 更多文档

- [compatibility.md](compatibility.md)：兼容性和验证边界。
- [docker/full-s6/README.md](docker/full-s6/README.md)：full-s6 构建、运行和 smoke。

## English

This is the `WeiYusc/rustdesk-server` downstream fork based on the official `rustdesk/rustdesk-server`. It self-hosts the RustDesk ID/relay services and is designed to work with `WeiYusc/rustdesk-api` and `WeiYusc/rustdesk-api-web` as a complete Web Admin/API/server stack.

### Current capabilities

- `hbbs`: RustDesk ID/Rendezvous server.
- `hbbr`: RustDesk relay server.
- `rustdesk-utils`: RustDesk server utilities.
- Reverse-proxy header boundary: by default, `X-Real-IP` / `X-Forwarded-For` are trusted only from loopback proxies. Set `TRUST_PROXY_HEADERS=1` only for trusted non-loopback reverse proxies.
- The repository keeps the official binary/compose deployment paths and adds a full-s6 integrated image build path.

### Relationship with API and Web frontend

The complete management stack uses three repositories:

| Repository | Role |
| --- | --- |
| `WeiYusc/rustdesk-server` | `hbbs` / `hbbr` server and full-s6 image build entrypoint |
| `WeiYusc/rustdesk-api` | RustDesk API, accounts, address books, audit logs, admin endpoints |
| `WeiYusc/rustdesk-api-web` | Vue/Naive UI Web Admin frontend injected as API static assets after build |

### Build

```bash
cargo build --release
```

Artifacts are generated under `target/release/`:

- `hbbs`
- `hbbr`
- `rustdesk-utils`

### Basic deployment option

For production today, you can still follow the official OSS self-hosting flow and run `hbbs` / `hbbr` separately with a persistent server-key directory.

Reference: <https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/>

### full-s6 integrated image (reserved option)

This repository also has a local full-s6 image build path that packages these components into one Docker image:

- `hbbs`
- `hbbr`
- `rustdesk-api`
- built `rustdesk-api-web` Web Admin assets

Current status:

- Local build and smoke tests are verified.
- The image is still a local tag such as `rustdesk-server-full-s6:local`.
- **No Docker Hub/GHCR public image has been published yet.**
- Treat this as a reserved deployment option until the public image, tag strategy, upgrade, and rollback docs are finalized.

See [docker/full-s6/README.md](docker/full-s6/README.md).

### Verification boundary

Verified:

- Local build.
- Compose/binary baseline.
- Local full-s6 startup, Web Admin/API/server processes, admin login, and config endpoint.
- Basic WebSocket upgrade checks.

Still pending:

- Real two-client / two-identity RustDesk forced-login and connection flow.
- Public image publishing, long-term upgrade, and rollback workflow.
- Multi-architecture images and non-linux/amd64 targets.

### More docs

- [compatibility.md](compatibility.md): compatibility and verification boundary.
- [docker/full-s6/README.md](docker/full-s6/README.md): full-s6 build, runtime, and smoke test.
