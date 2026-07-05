# Preview 20260705 e1e8bbd docs-guide Release Notes

This note is for users and operators evaluating the `rustdesk-server-full-s6` integrated image. It describes what is included, what was verified, and what remains out of scope.

> This is a preview image, not a long-term stable release. No `latest` tag is published.

## Image

```text
ghcr.io/weiyusc/rustdesk-server-full-s6:preview-20260705-e1e8bbd-docs-guide
```

Digest:

```text
sha256:0b0046ae20c4cbc88b7cec9eaa8ef96440119258c9286deceba0d8fcebc61ce7
```

Source fingerprints:

| Component | Fingerprint | Notes |
| --- | --- | --- |
| `rustdesk-server` | `4cfc50f` | full-s6 image build metadata |
| `rustdesk-api` | `23b7580` | API email-error handling updates |
| `rustdesk-api-web` | `e1e8bbd` | client login and server-configuration troubleshooting docs |

## Highlights

### 1. Integrated image build metadata

The image exposes `/api/build-info`, which reports the server, API, and Web Admin fingerprints embedded in the running container. This helps during upgrades and troubleshooting.

### 2. Web Admin safety hints and documentation link

The **System settings / Server security** page now keeps the UI concise:

- confirm client configuration and login state before enabling forced login;
- show the verified behavior that logged-out clients are rejected and logged-in clients can connect;
- link to the detailed documentation instead of placing a long guide inside the settings page.

### 3. Client configuration troubleshooting docs

The API-Web repository now includes Chinese and English troubleshooting guides covering:

- API server, ID server, relay server, and Key roles;
- checklist before enabling `MUST_LOGIN`;
- common client error matrix;
- why a wrong client-side relay-server field may still connect.

Chinese guide:

```text
https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.zh-CN.md
```

English guide:

```text
https://github.com/WeiYusc/rustdesk-api-web/blob/master/docs/client-login-and-server-config.en.md
```

## Verified scope

This preview image has been verified for:

- successful GitHub Actions build;
- post-build smoke test;
- GHCR pullability;
- registry digest lookup;
- healthy test-host deployment using the GHCR image;
- accessible `/api/version` and `/api/build-info`;
- browser login to Web Admin;
- documentation link visible on the Server security page;
- no recent panic, fatal, traceback, or migration-failed log matches during final verification.

## Known limits

- This is a preview tag, not a stable semantic-version release.
- No `latest` tag is published.
- The primary validation target is `linux/amd64`.
- The Web Admin `MUST_LOGIN` toggle applies runtime state; after the container or `hbbs` restarts, the environment-variable default applies again.
- The real official-client connection matrix was not repeated for these release notes. Historical conclusions are documented in the troubleshooting guide.
- A wrong client-side relay-server field may not fail by itself, because the ID server can return the server-configured relay address during negotiation.

## Upgrade guidance

If you already run an older full-s6 image in a test environment, follow the [upgrade and rollback guide](upgrade-rollback.en.md). Before upgrading, confirm that:

1. `/data` and `/app/data` are backed up;
2. the current image and environment are recorded;
3. a rollback container will be kept;
4. the new image digest is confirmed;
5. `/api/build-info` is checked after upgrade.

For production use, validate the image in a separate test environment before scheduling an upgrade window.

## Post-upgrade checklist

```bash
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'

curl -fsS http://127.0.0.1:21114/api/version
curl -fsS http://127.0.0.1:21114/api/build-info
curl -fsSI http://127.0.0.1:21114/_admin/ | head -5
```

If an HTTPS domain is used, verify that domain as well.
