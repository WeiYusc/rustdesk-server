# RustDesk Server / RustDesk 服务端

[中文](#中文) · [English](#english)

## 中文

`WeiYusc/rustdesk-server` 是基于官方 `rustdesk/rustdesk-server` 的下游仓库，用于自托管 RustDesk 标识服务器和中继服务器，并提供 full-s6 集成镜像，把服务端、接口服务和 Web 管理后台组合成一个容器。

### 快速开始

1. 只需要官方标识/中继服务：参考 [RustDesk 官方自托管文档](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/)。
2. 需要完整管理栈：阅读 [full-s6 集成镜像部署指南](docs/full-s6/deployment.zh-CN.md)。
3. 想直接复制 Docker Compose 配置模板：阅读 [Docker Compose 模板](docs/full-s6/compose.zh-CN.md)。
4. 已经部署旧版本：先阅读 [升级与回滚指南](docs/full-s6/upgrade-rollback.zh-CN.md)。
5. 需要配置客户端登录或排查连接问题：阅读 [客户端登录、MUST_LOGIN 与服务器配置排障指南](https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.zh-CN.md)。

### 文档目录

| 任务 | 中文 | English |
| --- | --- | --- |
| 部署 full-s6 集成镜像 | [部署指南](docs/full-s6/deployment.zh-CN.md) | [Deployment guide](docs/full-s6/deployment.en.md) |
| 复制 Docker Compose 配置模板 | [Compose 模板](docs/full-s6/compose.zh-CN.md) | [Compose template](docs/full-s6/compose.en.md) |
| 升级与回滚 | [升级与回滚指南](docs/full-s6/upgrade-rollback.zh-CN.md) | [Upgrade and rollback guide](docs/full-s6/upgrade-rollback.en.md) |
| 当前稳定镜像说明 | [v0.1.0 发布说明](docs/full-s6/release-notes-v0.1.0.zh-CN.md) | [v0.1.0 release notes](docs/full-s6/release-notes-v0.1.0.en.md) |
| 当前预览镜像说明 | [Preview 20260705 发布说明](docs/full-s6/release-notes-preview-20260705.zh-CN.md) | [Preview 20260705 release notes](docs/full-s6/release-notes-preview-20260705.en.md) |
| 发布检查清单 | [发布检查清单](docs/full-s6/release-checklist.zh-CN.md) | [Release checklist](docs/full-s6/release-checklist.en.md) |
| 本地构建与 smoke | [docker/full-s6/README.md](docker/full-s6/README.md) | [docker/full-s6/README.md](docker/full-s6/README.md) |
| 兼容性与验证边界 | [compatibility.md](compatibility.md) | [compatibility.md](compatibility.md) |

### 当前推荐镜像

稳定版本：

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0
```

稳定版浮动标签：

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:latest
```

`v0.1.0` 是面向 `linux/amd64` 的 full-s6 稳定发布标签。发布判断基于当前预览线的构建、GHCR 拉取、测试机部署、接口服务、管理后台、Compose smoke、备份/替换/回滚演练，以及已接受的历史真实客户端矩阵证据；本次稳定发布未重新执行完整真实官方客户端矩阵。详细摘要和边界见 [v0.1.0 发布说明](docs/full-s6/release-notes-v0.1.0.zh-CN.md)。

> 需要可复现部署或排障时，请优先固定 `v0.1.0` 或摘要；`latest` 会跟随最新稳定版移动。预览通道 `preview` 继续保留给测试环境，不自动等同于稳定版。

### 组件关系

完整管理栈由三个仓库组成：

| 仓库 | 作用 |
| --- | --- |
| `WeiYusc/rustdesk-server` | `hbbs` / `hbbr` 服务端，以及 full-s6 集成镜像构建入口 |
| `WeiYusc/rustdesk-api` | 账号、地址簿、审计、管理接口和接口服务 |
| `WeiYusc/rustdesk-api-web` | Web 管理后台，构建后注入到集成镜像 |

### 本仓库能力

- `hbbs`：RustDesk 标识服务器，用于设备发现和连接协商。
- `hbbr`：RustDesk 中继服务器，用于无法直连时的数据转发。
- `rustdesk-utils`：RustDesk 服务端工具。
- full-s6 集成镜像：把 `hbbs`、`hbbr`、接口服务和 Web 管理后台放入单个容器。
- 反向代理头安全边界：默认只信任本机代理传入的 `X-Real-IP` / `X-Forwarded-For`；非本机可信代理需显式启用 `TRUST_PROXY_HEADERS=1`。

### 构建服务端二进制

```bash
cargo build --release
```

生成文件位于 `target/release/`：

- `hbbs`
- `hbbr`
- `rustdesk-utils`

### 已知边界

- 当前 full-s6 稳定镜像仅声明支持已验证的 `linux/amd64`。
- `MUST_LOGIN` 的管理后台开关是运行时状态；容器或 `hbbs` 重启后会回到环境变量默认值。
- 当前不发布、不声明 `linux/arm64` 或多架构镜像支持；多架构需要后续独立运行时验证。
- 真实客户端连接结果会受客户端版本、网络和配置影响；客户端登录与配置问题请参考排障文档。

## English

`WeiYusc/rustdesk-server` is a downstream fork of the official `rustdesk/rustdesk-server`. It self-hosts the RustDesk ID and relay services and provides a full-s6 integrated image that combines the server, API service, and Web Admin into one container.

### Quick start

1. If you only need the official ID/relay services, follow the [upstream RustDesk self-hosting documentation](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/).
2. If you need the complete management stack, read the [full-s6 deployment guide](docs/full-s6/deployment.en.md).
3. If you want a copyable Compose template, read the [Docker Compose template](docs/full-s6/compose.en.md).
4. If you already run an older image, read the [upgrade and rollback guide](docs/full-s6/upgrade-rollback.en.md) first.
5. For client login or connection troubleshooting, read the [client login and server configuration guide](https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.en.md).

### Documentation map

| Task | 中文 | English |
| --- | --- | --- |
| Deploy the full-s6 integrated image | [部署指南](docs/full-s6/deployment.zh-CN.md) | [Deployment guide](docs/full-s6/deployment.en.md) |
| Copy Docker Compose template | [Compose 模板](docs/full-s6/compose.zh-CN.md) | [Compose template](docs/full-s6/compose.en.md) |
| Upgrade and rollback | [升级与回滚指南](docs/full-s6/upgrade-rollback.zh-CN.md) | [Upgrade and rollback guide](docs/full-s6/upgrade-rollback.en.md) |
| Current stable image | [v0.1.0 发布说明](docs/full-s6/release-notes-v0.1.0.zh-CN.md) | [v0.1.0 release notes](docs/full-s6/release-notes-v0.1.0.en.md) |
| Current preview image | [Preview 20260705 发布说明](docs/full-s6/release-notes-preview-20260705.zh-CN.md) | [Preview 20260705 release notes](docs/full-s6/release-notes-preview-20260705.en.md) |
| Release checklist | [发布检查清单](docs/full-s6/release-checklist.zh-CN.md) | [Release checklist](docs/full-s6/release-checklist.en.md) |
| Local build and smoke | [docker/full-s6/README.md](docker/full-s6/README.md) | [docker/full-s6/README.md](docker/full-s6/README.md) |
| Compatibility and validation boundary | [compatibility.md](compatibility.md) | [compatibility.md](compatibility.md) |

### Current recommended image

Stable version:

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0
```

Stable moving tag:

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:latest
```

`v0.1.0` is the stable full-s6 release tag for `linux/amd64`. The release decision is based on the current preview line's build, GHCR pull, test-host deployment, API, Web Admin, Compose smoke, backup/replacement/rollback rehearsal, and accepted existing real-client matrix evidence; the full real official-client matrix was not rerun for this stable release. See the [v0.1.0 release notes](docs/full-s6/release-notes-v0.1.0.en.md) for details and limits.

> For reproducible deployment and troubleshooting, prefer `v0.1.0` or a digest. The `latest` tag follows the newest stable release and can move. The `preview` channel remains for test environments and is not automatically equivalent to stable.

### Component relationship

The complete management stack uses three repositories:

| Repository | Role |
| --- | --- |
| `WeiYusc/rustdesk-server` | `hbbs` / `hbbr` server and full-s6 image build entrypoint |
| `WeiYusc/rustdesk-api` | accounts, address books, audit logs, admin endpoints, and API service |
| `WeiYusc/rustdesk-api-web` | Web Admin frontend injected into the integrated image after build |

### Repository capabilities

- `hbbs`: RustDesk ID/rendezvous server for device discovery and connection negotiation.
- `hbbr`: RustDesk relay server for traffic relay when direct connection is unavailable.
- `rustdesk-utils`: RustDesk server utilities.
- full-s6 integrated image: packages `hbbs`, `hbbr`, the API service, and Web Admin into one container.
- Reverse-proxy header boundary: by default, `X-Real-IP` / `X-Forwarded-For` are trusted only from loopback proxies. Set `TRUST_PROXY_HEADERS=1` only for trusted non-loopback reverse proxies.

### Build server binaries

```bash
cargo build --release
```

Artifacts are generated under `target/release/`:

- `hbbs`
- `hbbr`
- `rustdesk-utils`

### Known limits

- The current full-s6 stable image only claims validated `linux/amd64` support.
- The Web Admin `MUST_LOGIN` toggle applies runtime state; after the container or `hbbs` restarts, the environment-variable default applies again.
- `linux/arm64` and multi-architecture images are not published or claimed in this release; they require separate runtime validation later.
- Real client connection behavior depends on client version, network conditions, and configuration. See the troubleshooting guide for client login and server configuration issues.
