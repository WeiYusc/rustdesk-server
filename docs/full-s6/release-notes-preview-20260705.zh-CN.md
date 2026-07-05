# Preview 20260705 e1e8bbd docs-guide 发布说明

本文面向正在评估或试用 `rustdesk-server-full-s6` 集成镜像的用户和运维人员，说明本次预览镜像包含的内容、验证范围和已知边界。

> 这是预览版本，不是长期稳定版本；当前没有发布 `latest` 标签。

## 镜像

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:preview-20260705-e1e8bbd-docs-guide
```

摘要：

```text
sha256:0b0046ae20c4cbc88b7cec9eaa8ef96440119258c9286deceba0d8fcebc61ce7
```

源码指纹：

| 组件 | 指纹 | 说明 |
| --- | --- | --- |
| `rustdesk-server` | `4cfc50f` | full-s6 镜像构建信息 |
| `rustdesk-api` | `23b7580` | 接口服务邮件错误处理等修正 |
| `rustdesk-api-web` | `e1e8bbd` | 客户端登录与服务器配置排障文档入口 |

## 主要变化

### 1. 集成镜像包含构建信息

镜像内置 `/api/build-info`，可查看当前容器包含的服务端、接口服务和管理前端指纹。升级和排障时可以用它确认实际运行版本。

### 2. 管理后台增加轻量提示和文档入口

“系统设置 / 服务端安全”页面保留简短提示：

- 开启强制登录前，先确认客户端配置和登录状态；
- 已验证未登录客户端会被拒绝，已登录客户端可连接；
- 详细说明移动到文档，避免设置页过于复杂。

### 3. 新增客户端配置排障文档

API-Web 仓库新增中英文文档，覆盖：

- 接口服务地址、标识服务器、中继服务器和 Key 的作用；
- 启用 `MUST_LOGIN` 前的检查清单；
- 常见客户端错误矩阵；
- “客户端中继服务器字段填错但仍可能连接”的原因说明。

中文文档：

```text
https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.zh-CN.md
```

英文文档：

```text
https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.en.md
```

## 已验证范围

本次预览镜像已验证：

- GitHub Actions 构建成功；
- 构建后 smoke 通过；
- GHCR 镜像可拉取；
- 镜像摘要可通过 Registry 查询；
- 测试机可运行该 GHCR 镜像并保持健康；
- `/api/version` 和 `/api/build-info` 可访问；
- 管理后台可通过浏览器打开并登录；
- “服务端安全”页面显示文档入口；
- 近期日志未发现 panic、fatal、traceback、migration failed 等异常。

## 已知边界

- 当前标签是预览标签，不是正式语义化版本。
- 当前未发布 `latest` 标签。
- 主要验证平台是 `linux/amd64`。
- `MUST_LOGIN` 的管理后台开关是运行时状态；容器或 `hbbs` 重启后，会回到环境变量默认值。
- 本次发布说明没有重复执行真实官方客户端连接矩阵验证；相关历史结论已记录在客户端配置排障文档中。
- 只把客户端本地中继服务器字段填错，不一定导致连接失败，因为标识服务器可能在协商中返回服务端配置的中继服务器地址。

## 升级建议

如果你已经在测试环境使用旧的 full-s6 镜像，可以按[升级与回滚指南](upgrade-rollback.zh-CN.md)升级。升级前请确认：

1. 已备份 `/data` 和 `/app/data`；
2. 已记录当前镜像和环境变量；
3. 已准备回滚容器；
4. 已确认新镜像摘要；
5. 升级后检查 `/api/build-info`。

如果你正在生产环境使用旧镜像，建议先在独立测试环境验证，再安排升级窗口。

## 升级后检查清单

```bash
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'

curl -fsS http://127.0.0.1:21114/api/version
curl -fsS http://127.0.0.1:21114/api/build-info
curl -fsSI http://127.0.0.1:21114/_admin/ | head -5
```

如果对外使用 HTTPS 域名，也请检查域名访问。
