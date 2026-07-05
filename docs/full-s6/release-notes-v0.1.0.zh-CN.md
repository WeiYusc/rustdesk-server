# RustDesk full-s6 v0.1.0 发布说明

> 这是 `rustdesk-server-full-s6` 的第一个稳定标签，范围限定为已验证的 `linux/amd64` 集成镜像。

## 镜像

稳定标签：

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0
```

稳定版浮动标签：

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:latest
```

`latest` 会随最新稳定版移动；需要可复现部署、排障或回滚时，请固定 `v0.1.0` 或摘要。

预览通道继续保留：

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:preview
```

`preview` 用于愿意跟随预览更新的测试环境，不自动等同于稳定版。

## 范围

`v0.1.0` 仅适用于 `linux/amd64` 的 full-s6 集成镜像。该镜像包含：

- `hbbs`：RustDesk 标识服务器；
- `hbbr`：RustDesk 中继服务器；
- `rustdesk-api`：账号、地址簿、审计和管理接口；
- 已构建的 `rustdesk-api-web` Web 管理后台；
- s6 进程监督和健康检查。

本版本不声明：

- `linux/arm64` 支持；
- 多架构镜像支持；
- 一键安装脚本；
- 生产 SLA；
- 未验证客户端版本或未验证网络环境下的连接行为。

## 主要验证证据

稳定发布判断基于以下已完成验证：

- `v0.1.0-preview.1` 预览线完成构建、GHCR 拉取、测试机部署、接口服务、管理后台和基础浏览器验证；
- Docker Compose 模板已从文档提取并进行实机 smoke；
- 测试机主服务运行健康；
- `/api/version`、`/api/build-info`、`/_admin/` 验证通过；
- `21114`-`21119/tcp` 与 `21116/udp` 监听验证通过；
- 升级/回滚演练已验证 `/data` 与 `/app/data` 的备份、容器替换和回滚流程；
- 日志扫描未发现 `fatal`、`panic`、`traceback`、`migration failed`、端口占用等严重错误。

## 客户端验证说明

本次 `v0.1.0` stable gate 未重新执行完整真实官方客户端矩阵。发布判断沿用此前已接受的客户端矩阵验证结论，并保留“客户端本地中继服务器字段填错仍可能连接”的边界说明。

已接受的既有结论包括：

```text
MUST_LOGIN=Y 未登录客户端 -> LOGIN_REQUIRED
MUST_LOGIN=Y 已登录客户端 -> 可连接
错误 Key -> invalid public key
错误 API Server -> 无 webauth / 登录失败
错误 ID Server -> 账号登录可能成功，但设备离线 / 连接标识服务器失败
错误 Relay Server -> 不一定失败，因为 hbbs 可能在协商中返回服务端配置的 relay
```

更多客户端登录、强制登录和服务器配置排障说明见：

```text
https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.zh-CN.md
```

## 升级与回滚

升级前必须备份持久化数据：

```text
/data
/app/data
```

如果使用 Compose 模板，对应宿主机目录通常是：

```text
./data/server
./data/app
```

如果使用部署指南中的 `docker run` 示例，对应宿主机目录通常是：

```text
/opt/rustdesk-full-s6/server-data
/opt/rustdesk-full-s6/app-data
```

容器回滚不等于数据回滚；如果新版本执行了数据迁移或写入，必要时需要从备份恢复数据目录。

## 文档入口

- [部署指南](deployment.zh-CN.md)
- [Docker Compose 模板](compose.zh-CN.md)
- [升级与回滚指南](upgrade-rollback.zh-CN.md)
- [发布检查清单](release-checklist.zh-CN.md)

## 已知边界

- 当前稳定范围仅限 `linux/amd64`。
- 暂不发布、不声明 `linux/arm64` 或多架构支持。
- `MUST_LOGIN` 的管理后台开关是运行时状态；容器或 `hbbs` 重启后会回到环境变量默认值。
- `latest` 是稳定版浮动标签，会随新的稳定版移动。
- `preview` 保持为预览通道，不自动指向稳定版。
