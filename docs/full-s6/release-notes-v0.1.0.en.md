# RustDesk full-s6 v0.1.0 Release Notes

> This is the first stable tag for `rustdesk-server-full-s6`, scoped to the validated `linux/amd64` integrated image.

## Images

Stable tag:

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:v0.1.0
```

Moving stable tag:

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:latest
```

`latest` follows the newest stable release. For reproducible deployment, troubleshooting, or rollback, pin `v0.1.0` or a digest.

The preview channel remains available:

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:preview
```

`preview` is for test environments that intentionally follow preview updates. It is not automatically equivalent to stable.

## Scope

`v0.1.0` applies only to the `linux/amd64` full-s6 integrated image. The image includes:

- `hbbs`: RustDesk ID/rendezvous server;
- `hbbr`: RustDesk relay server;
- `rustdesk-api`: account, address-book, audit, and admin API service;
- built `rustdesk-api-web` Web Admin assets;
- s6 process supervision and health checks.

This release does not claim:

- `linux/arm64` support;
- multi-architecture image support;
- an installer script;
- production SLA;
- behavior for unverified client versions or unverified network environments.

## Validation evidence

The stable release decision is based on these completed checks:

- the `v0.1.0-preview.1` preview line passed build, GHCR pull, test-host deployment, API, Web Admin, and basic browser validation;
- the Docker Compose template was extracted from the docs and smoke-tested on a real host;
- the test-host main service is healthy;
- `/api/version`, `/api/build-info`, and `/_admin/` passed checks;
- `21114`-`21119/tcp` and `21116/udp` listeners were verified;
- upgrade/rollback rehearsal verified backups for `/data` and `/app/data`, container replacement, and rollback;
- log scans found no severe `fatal`, `panic`, `traceback`, `migration failed`, port-conflict, or permission failures.

## Client validation note

The full real official-client matrix was not rerun for the `v0.1.0` stable gate. The release carries forward the existing accepted client-matrix evidence from prior validation, with the relay-server fallback caveat documented.

Accepted prior conclusions:

```text
MUST_LOGIN=Y unauthenticated client -> LOGIN_REQUIRED
MUST_LOGIN=Y authenticated client -> connects
wrong Key -> invalid public key
wrong API Server -> no webauth / login failure
wrong ID Server -> account login can work but peers offline / connect-to-ID-server failure
wrong Relay Server -> may still connect because hbbs can return the server-configured relay
```

For client login, forced login, and server configuration troubleshooting, see:

```text
https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.en.md
```

## Upgrade and rollback

Before upgrading, back up persistent data:

```text
/data
/app/data
```

If you use the Compose template, the host paths are usually:

```text
./data/server
./data/app
```

If you use the deployment guide's `docker run` example, the host paths are usually:

```text
/opt/rustdesk-full-s6/server-data
/opt/rustdesk-full-s6/app-data
```

Container rollback is not the same as data rollback. If a new version performs migrations or writes data, restoring the data directories from backup may be required.

## Documentation

- [Deployment guide](deployment.en.md)
- [Docker Compose template](compose.en.md)
- [Upgrade and rollback guide](upgrade-rollback.en.md)
- [Release checklist](release-checklist.en.md)

## Known limits

- The stable scope is limited to `linux/amd64`.
- `linux/arm64` and multi-architecture support are not published or claimed.
- The Web Admin `MUST_LOGIN` toggle applies runtime state; after the container or `hbbs` restarts, the environment-variable default applies again.
- `latest` is the moving stable tag and can move when a newer stable release is published.
- `preview` remains the preview channel and does not automatically point to stable.
