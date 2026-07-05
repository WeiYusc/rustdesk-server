# Full-s6 Integrated Image / full-s6 集成镜像

[中文](#中文) · [English](#english)

## 中文

full-s6 是 `WeiYusc/rustdesk-server` 的单容器集成方案，用 s6-overlay 同时管理：

- `hbbs`
- `hbbr`
- `rustdesk-api`
- 构建后的 `rustdesk-api-web` Web Admin，注入到 `/app/resources/admin`

> 状态说明：该方案已经完成本地构建、smoke 验证和 GHCR 预览镜像发布。面向普通部署请优先阅读 `docs/full-s6/` 下的部署、升级和发布说明；本文主要保留本地构建与开发验证流程。

### 构建

在 server 仓库根目录执行：

```bash
RUSTDESK_API_SOURCE_DIR=/path/to/rustdesk-api \
RUSTDESK_API_WEB_SOURCE_DIR=/path/to/rustdesk-api-web \
RUSTDESK_FULL_S6_IMAGE=rustdesk-server-full-s6:local \
./scripts/build-full-s6-image.sh
```

默认输入：

- Server：当前仓库。
- API：`../reference-repos/WeiYusc_rustdesk-api`。
- Web Admin：`../reference-repos/WeiYusc_rustdesk-api-web`。
- 镜像标签：`rustdesk-server-full-s6:local`。

构建脚本会把 API 仓库复制到临时目录再编译，避免 `GOFLAGS=-mod=mod` 在源仓库中留下 `go.mod` 漂移。

### 本地 smoke

```bash
./scripts/smoke-full-s6-image.sh rustdesk-server-full-s6:local
```

smoke 会验证：

- s6 作为 PID 1 启动。
- `hbbr`、`hbbs`、`api` 均由 s6 管理并运行。
- `/data` 生成 RustDesk server key。
- `/_admin/` 返回 200。
- 使用 API 日志中的首次随机管理员密码完成登录。
- `/api/admin/user/current` 和 `/api/admin/config/server` 可访问。

### 运行示例（本地构建镜像）

普通部署请不要直接复制本节命令；请优先使用 [部署指南](../../docs/full-s6/deployment.zh-CN.md) 中的 GHCR 镜像命令。本节用于本地构建镜像的开发验证。

请把域名、URL、卷名替换为你的部署值：

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
  -v rustdesk-data:/data \
  -v rustdesk-api-data:/app/data \
  -e RELAY=relay.example.com:21117 \
  -e RUSTDESK_API_RUSTDESK_ID_SERVER=id.example.com:21116 \
  -e RUSTDESK_API_RUSTDESK_RELAY_SERVER=relay.example.com:21117 \
  -e RUSTDESK_API_RUSTDESK_API_SERVER=https://api.example.com \
  -e RUSTDESK_API_RUSTDESK_KEY_FILE=/data/id_ed25519.pub \
  -e RUSTDESK_API_JWT_KEY='<generate-a-long-random-secret>' \
  rustdesk-server-full-s6:local
```

首次启动会在 API 日志中打印随机管理员密码。请及时记录或使用 `apimain reset-admin-pwd` 重置，不要在公开 issue / 文档中粘贴真实密码。

### 相关发布文档

- [部署指南](../../docs/full-s6/deployment.zh-CN.md) / [Deployment guide](../../docs/full-s6/deployment.en.md)
- [升级与回滚指南](../../docs/full-s6/upgrade-rollback.zh-CN.md) / [Upgrade and rollback guide](../../docs/full-s6/upgrade-rollback.en.md)
- [Preview 20260705 发布说明](../../docs/full-s6/release-notes-preview-20260705.zh-CN.md) / [Release notes](../../docs/full-s6/release-notes-preview-20260705.en.md)

### 生产注意事项

- 当前 full-s6 镜像仍按上游 s6 模式以 root 启动，便于 PID 1 进程管理、密钥注入和卷权限处理；非 root 运行是后续加固事项。
- 建议持久化两个卷：`/data` 保存服务端密钥，`/app/data` 保存接口服务数据库、上传文件和运行数据。
- 如果启用 `MUST_LOGIN`，服务端与接口服务必须共享同一个 `RUSTDESK_API_JWT_KEY`，并在目标环境完成真实客户端验证。
- 当前 smoke 证明集成镜像可启动并服务 Web Admin、接口服务和服务端进程；真实客户端连接仍受客户端版本、网络和配置影响。

## English

The full-s6 path is a single-container integration option for `WeiYusc/rustdesk-server`. It uses s6-overlay to supervise:

- `hbbs`
- `hbbr`
- `rustdesk-api`
- built `rustdesk-api-web` Web Admin assets injected into `/app/resources/admin`

> Status: local build, smoke tests, and a GHCR preview image are verified. For normal deployments, prefer the deployment, upgrade, and release-note documents under `docs/full-s6/`; this file focuses on local build and development validation.

### Build

Run from the server repository root:

```bash
RUSTDESK_API_SOURCE_DIR=/path/to/rustdesk-api \
RUSTDESK_API_WEB_SOURCE_DIR=/path/to/rustdesk-api-web \
RUSTDESK_FULL_S6_IMAGE=rustdesk-server-full-s6:local \
./scripts/build-full-s6-image.sh
```

Default inputs:

- Server: current repository.
- API: `../reference-repos/WeiYusc_rustdesk-api`.
- Web Admin: `../reference-repos/WeiYusc_rustdesk-api-web`.
- Image tag: `rustdesk-server-full-s6:local`.

The build script copies the API repository into a temporary directory before compiling, so `GOFLAGS=-mod=mod` does not leave `go.mod` drift in the source checkout.

### Local smoke

```bash
./scripts/smoke-full-s6-image.sh rustdesk-server-full-s6:local
```

The smoke test verifies:

- s6 starts as PID 1.
- `hbbr`, `hbbs`, and `api` are supervised and running.
- RustDesk server key material is generated in `/data`.
- `/_admin/` returns 200.
- Admin login works with the first-run random password printed in API logs.
- `/api/admin/user/current` and `/api/admin/config/server` work.

### Runtime example for a locally built image

For normal deployments, do not copy this command directly. Prefer the GHCR image command in the [deployment guide](../../docs/full-s6/deployment.en.md). This section is for local-build development validation.

Replace domains, URLs, and volume names with your deployment values:

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
  -v rustdesk-data:/data \
  -v rustdesk-api-data:/app/data \
  -e RELAY=relay.example.com:21117 \
  -e RUSTDESK_API_RUSTDESK_ID_SERVER=id.example.com:21116 \
  -e RUSTDESK_API_RUSTDESK_RELAY_SERVER=relay.example.com:21117 \
  -e RUSTDESK_API_RUSTDESK_API_SERVER=https://api.example.com \
  -e RUSTDESK_API_RUSTDESK_KEY_FILE=/data/id_ed25519.pub \
  -e RUSTDESK_API_JWT_KEY='<generate-a-long-random-secret>' \
  rustdesk-server-full-s6:local
```

The first boot prints a random admin password in API logs. Capture it securely or reset it with `apimain reset-admin-pwd`; do not paste real passwords into public issues or docs.

### Related release documentation

- [部署指南](../../docs/full-s6/deployment.zh-CN.md) / [Deployment guide](../../docs/full-s6/deployment.en.md)
- [升级与回滚指南](../../docs/full-s6/upgrade-rollback.zh-CN.md) / [Upgrade and rollback guide](../../docs/full-s6/upgrade-rollback.en.md)
- [Preview 20260705 发布说明](../../docs/full-s6/release-notes-preview-20260705.zh-CN.md) / [Release notes](../../docs/full-s6/release-notes-preview-20260705.en.md)

### Production notes

- The current full-s6 image still follows the upstream s6 pattern and starts as root for PID 1 supervision, key injection, and mounted-volume ownership. Non-root runtime is a later hardening slice.
- Persist both `/data` for server keys and `/app/data` for API DB, uploads, and runtime data.
- If enabling `MUST_LOGIN`, the server and API must share the same `RUSTDESK_API_JWT_KEY`, and target-environment real-client validation is required.
- The current smoke proves the integrated image starts and serves Web Admin, API, and server processes; real client connectivity still depends on client version, network conditions, and configuration.
