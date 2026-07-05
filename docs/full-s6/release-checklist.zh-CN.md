# RustDesk full-s6 预览发布检查清单

本文面向维护者，用于发布或刷新 `rustdesk-server-full-s6` 预览镜像。它不是普通用户部署指南；普通部署请先阅读 [部署指南](deployment.zh-CN.md) 或 [Docker Compose 模板](compose.zh-CN.md)。

目标是让每次预览发布都有同一套可复用流程：固定标签、可选浮动 `preview`、不误发 `latest`、GHCR 验证、测试机 smoke、Compose smoke、Release 页面和收口归档。

## 0. 发布策略

预览阶段默认使用三层策略：

```text
vX.Y.Z-preview.N  固定预览标签，用于复现、排障、回滚
preview           浮动预览标签，用于愿意跟随最新预览的测试环境
latest            不发布，留给未来稳定版
```

除非明确决定进入稳定版，否则不要发布 `latest`。

## 1. 发布前同步和指纹确认

在 `rustdesk-server` 仓库中先同步用户自己的远端分支：

```bash
git fetch origin --prune --tags
git status --short --branch
git rev-list --left-right --count HEAD...origin/$(git branch --show-current)
git log -1 --oneline
```

要求：

- 工作树干净；
- 本地分支没有落后远端；
- 待发布提交就是要打标签或触发 workflow 的提交；
- 如涉及 `rustdesk-api`、`rustdesk-api-web`，记录完整提交 SHA，不要只记录短 SHA。

记录发布输入：

```text
rustdesk-server: <full-server-sha>
rustdesk-api: <full-api-sha>
rustdesk-api-web: <full-web-sha>
image tag: vX.Y.Z-preview.N
```

## 2. 文档一致性检查

发布前确认这些文档的标签、摘要、边界描述一致：

```text
README.md
docs/full-s6/deployment.zh-CN.md
docs/full-s6/deployment.en.md
docs/full-s6/compose.zh-CN.md
docs/full-s6/compose.en.md
docs/full-s6/upgrade-rollback.zh-CN.md
docs/full-s6/upgrade-rollback.en.md
docs/full-s6/release-notes-*.zh-CN.md
docs/full-s6/release-notes-*.en.md
```

重点检查：

- 是否都推荐固定预览标签或摘要；
- 是否明确 `preview` 会移动；
- 是否明确没有发布 `latest`；
- Compose 模板中的镜像标签是否符合当前推荐；
- 升级文档是否明确备份 `/data` 和 `/app/data`；
- 文档示例是否只使用示例域名、占位符和 `[REDACTED]`，不要出现真实密码、token、域名、IP 或账号标识。

## 3. 创建固定预览标签

确认标签不存在：

```bash
git tag -l 'v*-preview*' --sort=-version:refname
git ls-remote --tags origin 'v*-preview*'
gh release list --repo WeiYusc/rustdesk-server --limit 20
```

创建并推送带注释源码标签：

```bash
git tag -a vX.Y.Z-preview.N \
  -m 'vX.Y.Z-preview.N full-s6 preview' \
  <server-commit>

git push origin refs/tags/vX.Y.Z-preview.N
```

## 4. 触发 GHCR 发布 workflow

触发固定标签发布时，`--ref` 应指向本次发布的固定源码标签或精确 server 提交，避免 `master` 后续移动导致镜像源码和 Release 声明不一致。`api_ref` 和 `api_web_ref` 使用完整 SHA，避免 `actions/checkout` 找不到短 SHA：

```bash
gh workflow run "publish full-s6 ghcr" \
  --repo WeiYusc/rustdesk-server \
  --ref vX.Y.Z-preview.N \
  -f image_tag=vX.Y.Z-preview.N \
  -f api_ref=<full-api-sha> \
  -f api_web_ref=<full-web-sha> \
  -f push_image=true
```

如果本次也要移动 `preview` 浮动标签，使用同一组 source ref 再触发一次发布；当前 workflow 每次只发布一个镜像标签，所以不要只在文档里声明 `preview`，必须实际发布并验证：

```bash
gh workflow run "publish full-s6 ghcr" \
  --repo WeiYusc/rustdesk-server \
  --ref vX.Y.Z-preview.N \
  -f image_tag=preview \
  -f api_ref=<full-api-sha> \
  -f api_web_ref=<full-web-sha> \
  -f push_image=true
```

因为两次构建时间和镜像标签不同，固定标签和 `preview` 的 digest 可能不同；Release 页面应说明 `preview` 是浮动标签，需要复现时固定命名标签或 digest。

等待并要求成功：

```bash
gh run list --repo WeiYusc/rustdesk-server --workflow "publish full-s6 ghcr" --limit 5
gh run watch <run-id> --repo WeiYusc/rustdesk-server --exit-status
```

记录：

```text
workflow run URL
image tag
digest
server/api/web 指纹
```

## 5. GHCR 验证

固定标签必须匿名可查：

```bash
docker buildx imagetools inspect \
  ghcr.io/weiyusc/rustdesk-server-full-s6:vX.Y.Z-preview.N
```

如果发布或刷新浮动 `preview` 标签，也验证：

```bash
docker buildx imagetools inspect \
  ghcr.io/weiyusc/rustdesk-server-full-s6:preview
```

确认 `latest` 没有被发布，除非本次明确进入稳定版。这个命令在预览阶段预期失败，脚本中不要直接放在 `set -e` 环境里裸跑，应捕获退出码或 HTTP 状态：

```bash
# 预览阶段期望 latest 查询失败或返回 404。
docker buildx imagetools inspect \
  ghcr.io/weiyusc/rustdesk-server-full-s6:latest || true
```

若使用 Registry V2 API，也记录 HTTP 状态和摘要：

```text
vX.Y.Z-preview.N -> HTTP 200, digest <sha256:...>
preview          -> HTTP 200, digest <sha256:...>（如果本次发布）
latest           -> HTTP 404（预览阶段期望）
```

## 6. 测试机固定标签 smoke

在测试机替换主服务前，先保留回滚容器和当前环境配置。替换后验证：

```bash
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'

curl -fsS http://127.0.0.1:21114/api/version
curl -fsS http://127.0.0.1:21114/api/build-info
curl -fsSI http://127.0.0.1:21114/_admin/ | head -5
```

还要检查：

- `21114`-`21119` TCP 端口；
- `21116/udp`；
- Web 管理后台能打开；
- 如需要登录验证，使用受控的测试机管理员密码文件，不要写入公开文档；
- 日志没有 `fatal`、`panic`、`traceback`、`migration failed`、`address already in use` 等严重错误；
- `MUST_LOGIN` 当前状态符合预期，且文档仍说明它是运行时状态。

## 7. Compose 模板 smoke

当 Compose 文档新增或变更时，必须从文档提取模板验证，而不是手写另一份 Compose：

1. 从 `docs/full-s6/compose.zh-CN.md` 或英文文档提取 `yaml` 和 `env` 代码块；
2. 保持镜像标签不变；
3. 只做避免冲突的 smoke 改动：

```text
container_name=rustdesk-full-s6-compose-smoke
23114-23119 -> 21114-21119
23116/udp -> 21116/udp
PUBLIC_HOST=127.0.0.1
API_SERVER=http://127.0.0.1:23114
RUSTDESK_API_JWT_KEY=<临时随机值>
MUST_LOGIN=N
```

执行：

```bash
docker compose config --quiet
docker compose up --detach
```

验证：

```bash
docker inspect rustdesk-full-s6-compose-smoke \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'

curl -fsS http://127.0.0.1:23114/api/version
curl -fsS http://127.0.0.1:23114/api/build-info
curl -fsSI http://127.0.0.1:23114/_admin/ | head -5
```

检查端口：

```text
23114/tcp
23115/tcp
23116/tcp
23116/udp
23117/tcp
23118/tcp
23119/tcp
```

执行前确认当前目录就是专用 smoke 目录，并扫描日志后清理：

```bash
pwd
docker compose down --volumes --remove-orphans
```

保留归档时排除 `.env`，因为它包含临时密钥。

## 8. GitHub Release 页面

Release 页面必须包含：

- 固定标签和摘要；
- 如发布了 `preview`，说明它是浮动标签并记录当前摘要；
- 明确 `latest` 未发布；
- server/API/Web 指纹；
- workflow run URL；
- 部署指南、升级回滚指南、Compose 模板入口；
- 已验证范围；
- 已知边界；
- 中文摘要。

创建或更新 Release：

```bash
gh release create vX.Y.Z-preview.N \
  --repo WeiYusc/rustdesk-server \
  --title 'RustDesk full-s6 vX.Y.Z-preview.N' \
  --notes-file /tmp/release.md \
  --prerelease \
  --verify-tag
```

或更新已有 Release：

```bash
gh release edit vX.Y.Z-preview.N \
  --repo WeiYusc/rustdesk-server \
  --notes-file /tmp/release.md
```

发布后读取验证：

```bash
gh release view vX.Y.Z-preview.N \
  --repo WeiYusc/rustdesk-server \
  --json tagName,name,isPrerelease,isDraft,url,body
```

## 9. 收口和归档

收口时记录：

```text
固定标签
digest
preview 标签和 digest（如有）
latest 是否不存在
workflow run URL
Release URL
测试机镜像和 health
/api/build-info 输出
Compose smoke 是否通过
rollback 容器名
清理了哪些临时文件
worklog 路径
最终 git 状态
```

最终同步检查：

```bash
git fetch origin --prune --tags
git status --short --branch
git rev-list --left-right --count HEAD...origin/$(git branch --show-current)
```

要求最终结果为干净，且 `HEAD...origin/<branch>` 为：

```text
0 0
```

## 10. 不要跳过的边界说明

预览阶段的发布报告必须明确：

- 这不是稳定生产版本；
- 主要验证平台；
- 是否重复了真实客户端连接矩阵；
- `MUST_LOGIN` 是运行时状态；
- `preview` 标签会移动；
- `latest` 未发布；
- 数据回滚和容器回滚不是一回事，升级前必须备份持久化数据。
