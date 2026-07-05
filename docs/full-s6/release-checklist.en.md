# RustDesk full-s6 preview release checklist

This document is for maintainers who publish or refresh the `rustdesk-server-full-s6` preview image. It is not the normal user deployment guide. For deployment, start with the [deployment guide](deployment.en.md) or the [Docker Compose template](compose.en.md).

The goal is to make every preview release follow the same reusable flow: pinned tag, optional moving `preview`, no accidental `latest`, GHCR verification, test-host smoke, Compose smoke, Release page update, and closeout archive.

## 0. Release policy

The preview line uses this tag policy by default:

```text
vX.Y.Z-preview.N  pinned preview tag for reproduction, troubleshooting, and rollback
preview           moving preview tag for test environments that intentionally follow the newest preview
latest            not published; reserved for a future stable release
```

Do not publish `latest` unless the project explicitly moves to a stable release.

## 1. Pre-release sync and source fingerprints

In the `rustdesk-server` repository, synchronize the user's own remote branch first:

```bash
git fetch origin --prune --tags
git status --short --branch
git rev-list --left-right --count HEAD...origin/$(git branch --show-current)
git log -1 --oneline
```

Requirements:

- the worktree is clean;
- the local branch is not behind the remote;
- the release commit is the commit used for tagging or workflow dispatch;
- if `rustdesk-api` and `rustdesk-api-web` are inputs, record full commit SHAs, not only short SHAs.

Record release inputs:

```text
rustdesk-server: <full-server-sha>
rustdesk-api: <full-api-sha>
rustdesk-api-web: <full-web-sha>
image tag: vX.Y.Z-preview.N
```

## 2. Documentation consistency check

Before publishing, make sure these documents agree on tags, digests, and boundaries:

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

Check especially that:

- the docs recommend a pinned preview tag or digest;
- the docs state that `preview` can move;
- the docs state that `latest` is not published;
- the Compose template image matches the current recommendation;
- the upgrade guide explicitly backs up `/data` and `/app/data`;
- examples use only sample domains, placeholders, and `[REDACTED]`; they must not include real passwords, tokens, domains, IP addresses, or account identifiers.

## 3. Create the pinned preview tag

Confirm that the tag does not already exist:

```bash
git tag -l 'v*-preview*' --sort=-version:refname
git ls-remote --tags origin 'v*-preview*'
gh release list --repo WeiYusc/rustdesk-server --limit 20
```

Create and push an annotated source tag:

```bash
git tag -a vX.Y.Z-preview.N \
  -m 'vX.Y.Z-preview.N full-s6 preview' \
  <server-commit>

git push origin refs/tags/vX.Y.Z-preview.N
```

## 4. Dispatch the GHCR publishing workflow

For the pinned tag release, `--ref` should point to the fixed source tag or exact server commit for this release. Do not hard-code a moving `master` ref, because it can make the built image source differ from the tag and Release notes. Use full SHAs for `api_ref` and `api_web_ref` so `actions/checkout` can resolve them reliably:

```bash
gh workflow run "publish full-s6 ghcr" \
  --repo WeiYusc/rustdesk-server \
  --ref vX.Y.Z-preview.N \
  -f image_tag=vX.Y.Z-preview.N \
  -f api_ref=<full-api-sha> \
  -f api_web_ref=<full-web-sha> \
  -f push_image=true
```

If this release should also move the `preview` tag, dispatch the same workflow a second time with the same source refs. The current workflow publishes one image tag per run, so do not only document `preview`; actually publish and verify it:

```bash
gh workflow run "publish full-s6 ghcr" \
  --repo WeiYusc/rustdesk-server \
  --ref vX.Y.Z-preview.N \
  -f image_tag=preview \
  -f api_ref=<full-api-sha> \
  -f api_web_ref=<full-web-sha> \
  -f push_image=true
```

Because the two builds have different build times and image tags, the pinned tag and `preview` may have different digests. The Release page should explain that `preview` is moving and that reproducible deployments should pin a named tag or digest.

Wait for success:

```bash
gh run list --repo WeiYusc/rustdesk-server --workflow "publish full-s6 ghcr" --limit 5
gh run watch <run-id> --repo WeiYusc/rustdesk-server --exit-status
```

Record:

```text
workflow run URL
image tag
digest
server/api/web fingerprints
```

## 5. GHCR verification

The pinned tag must be anonymously inspectable:

```bash
docker buildx imagetools inspect \
  ghcr.io/weiyusc/rustdesk-server-full-s6:vX.Y.Z-preview.N
```

If this release also publishes or refreshes the moving `preview` tag, verify it too:

```bash
docker buildx imagetools inspect \
  ghcr.io/weiyusc/rustdesk-server-full-s6:preview
```

Confirm that `latest` was not published unless this is an approved stable release. During preview releases this command is expected to fail, so do not run it bare inside a `set -e` script; capture the exit code or HTTP status:

```bash
# During preview releases, this should fail or return 404.
docker buildx imagetools inspect \
  ghcr.io/weiyusc/rustdesk-server-full-s6:latest || true
```

When using the Registry V2 API, record HTTP status and digest:

```text
vX.Y.Z-preview.N -> HTTP 200, digest <sha256:...>
preview          -> HTTP 200, digest <sha256:...> (if published)
latest           -> HTTP 404 (expected during preview)
```

## 6. Test-host smoke for the pinned tag

Before replacing the main service on the test host, preserve a rollback container and the current environment configuration. After replacement, verify:

```bash
docker inspect rustdesk-full-s6 \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'

curl -fsS http://127.0.0.1:21114/api/version
curl -fsS http://127.0.0.1:21114/api/build-info
curl -fsSI http://127.0.0.1:21114/_admin/ | head -5
```

Also check:

- TCP ports `21114`-`21119`;
- UDP `21116`;
- Web Admin opens in a browser;
- if login validation is required, use the controlled test-host admin password file and do not write it into public docs;
- logs do not contain severe failures such as `fatal`, `panic`, `traceback`, `migration failed`, or `address already in use`;
- the current `MUST_LOGIN` state is expected, and the docs still explain that it is runtime state.

## 7. Compose template smoke

When Compose docs are added or changed, validate by extracting the template from the docs, not by hand-writing a second Compose file:

1. Extract the fenced `yaml` and `env` code blocks from `docs/full-s6/compose.zh-CN.md` or the English doc.
2. Keep the image tag unchanged.
3. Make only non-conflicting smoke adaptations:

```text
container_name=rustdesk-full-s6-compose-smoke
23114-23119 -> 21114-21119
23116/udp -> 21116/udp
PUBLIC_HOST=127.0.0.1
API_SERVER=http://127.0.0.1:23114
RUSTDESK_API_JWT_KEY=<temporary random value>
MUST_LOGIN=N
```

Run:

```bash
docker compose config --quiet
docker compose up --detach
```

Verify:

```bash
docker inspect rustdesk-full-s6-compose-smoke \
  --format 'status={{.State.Status}} health={{.State.Health.Status}} image={{.Config.Image}}'

curl -fsS http://127.0.0.1:23114/api/version
curl -fsS http://127.0.0.1:23114/api/build-info
curl -fsSI http://127.0.0.1:23114/_admin/ | head -5
```

Check listeners:

```text
23114/tcp
23115/tcp
23116/tcp
23116/udp
23117/tcp
23118/tcp
23119/tcp
```

Before cleanup, confirm the current directory is the dedicated smoke directory. After scanning logs, clean up:

```bash
pwd
docker compose down --volumes --remove-orphans
```

If retaining artifacts, exclude `.env` because it contains a temporary secret.

## 8. GitHub Release page

The Release page must include:

- pinned tag and digest;
- moving `preview` tag and its current digest, if published;
- explicit statement that `latest` is not published;
- server/API/Web fingerprints;
- workflow run URL;
- deployment guide, upgrade/rollback guide, and Compose template links;
- verified scope;
- known limits;
- Chinese summary.

Create or update the Release:

```bash
gh release create vX.Y.Z-preview.N \
  --repo WeiYusc/rustdesk-server \
  --title 'RustDesk full-s6 vX.Y.Z-preview.N' \
  --notes-file /tmp/release.md \
  --prerelease \
  --verify-tag
```

Or update an existing Release:

```bash
gh release edit vX.Y.Z-preview.N \
  --repo WeiYusc/rustdesk-server \
  --notes-file /tmp/release.md
```

Read it back after publishing:

```bash
gh release view vX.Y.Z-preview.N \
  --repo WeiYusc/rustdesk-server \
  --json tagName,name,isPrerelease,isDraft,url,body
```

## 9. Closeout and archive

Closeout should record:

```text
pinned tag
digest
preview tag and digest, if any
whether latest is absent
workflow run URL
Release URL
test-host image and health
/api/build-info output
whether Compose smoke passed
rollback container name
which temporary files were cleaned
worklog path
final git status
```

Final sync check:

```bash
git fetch origin --prune --tags
git status --short --branch
git rev-list --left-right --count HEAD...origin/$(git branch --show-current)
```

The final result should be clean, with `HEAD...origin/<branch>` equal to:

```text
0 0
```

## 10. Boundaries that must not be skipped

Every preview release report must state:

- this is not a stable production release;
- the primary validated platform;
- whether the real official-client connection matrix was repeated;
- `MUST_LOGIN` is runtime state;
- the `preview` tag can move;
- `latest` is not published;
- data rollback and container rollback are not the same; persistent data must be backed up before upgrades.
