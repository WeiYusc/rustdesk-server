# RustDesk Server Modernization Compatibility Baseline

This document is the Stage 0 compatibility and source-boundary baseline for the `WeiYusc/rustdesk-server` downstream fork.

It records what is known before implementation. Do not treat `Source-present` or `Partial` rows as runtime-verified behavior.

## Baseline

| Field | Value |
|---|---|
| Downstream repository | `WeiYusc/rustdesk-server` |
| Upstream repository | `rustdesk/rustdesk-server` |
| Base branch | `master` |
| Base commit | `815c728837b8a091c9feeeabb423d543be3a7f8d` |
| Base commit date | `2026-02-17T01:28:35-05:00` |
| Base commit subject | `fix(security): update mio from 0.8.5 to 0.8.11 (#633)` |
| License posture | AGPL-3.0, following upstream |
| Deployment strategy | compose-first baseline retained; local full-s6 integrated image is now implemented and smoke-verified, but not yet published to Docker Hub/GHCR |
| Paired API project | `WeiYusc/rustdesk-api` |
| Paired frontend project | `WeiYusc/rustdesk-api-web`, built separately and injected into API release resources |

## Evidence Labels

| Label | Meaning |
|---|---|
| `Verified` | Proved by a local test, build, container smoke, real client smoke, or equivalent runtime evidence in this fork. |
| `Source-present` | Present in source or docs, but not yet executed in this fork. |
| `Partial` | Some evidence exists, but scope is incomplete or depends on another component. |
| `Reference-only` | Useful as a requirements or behavior reference; do not copy code/text/assets without an explicit license/source decision. |
| `Gap` | Needed or requested behavior appears absent from the current baseline. |
| `Deferred` | Intentionally out of current stage or blocked pending separate approval/evidence. |

## Repository and Source Boundary

| Source | Role | License / boundary |
|---|---|---|
| `rustdesk/rustdesk-server` | Official base | AGPL-3.0. Direct downstream base. Preserve license obligations. |
| `lejianwen/rustdesk-server` | Old API-compatible server fork | AGPL-3.0. Can be used as source evidence for behavior, but port narrowly and verify against current official base. |
| `lejianwen/rustdesk-server-s6` | Old integrated image reference | Currently unavailable/unresolved through GitHub API/git in this environment. Do not use code until source and license are recovered. |
| `WeiYusc/rustdesk-api` | Paired API service | MIT. Treat as runtime/config contract; do not vendor API code unless explicitly planned. |
| `WeiYusc/rustdesk-api-web` | Paired API Web Admin frontend | Separate frontend input; CI/release should build it and inject `dist` into API `resources/admin`. |
| `databk/rustdesk-console` | Console/ops feature reference | AGPL-3.0. Reference-only for feature inventory unless license strategy changes. |
| `lantongxue/rustdesk-api-server-pro` | API/admin feature reference | AGPL-3.0. Reference-only; do not copy source/UI/text/assets. |
| `liyan-lucky/rustdesk-api-server-pro` | API/admin compatibility reference | AGPL-3.0. Reference-only; do not copy source/UI/text/assets. |

## Compatibility Matrix

| Area | Current status | Evidence | Next validation gate |
|---|---|---|---|
| Official hbbs/hbbr base | Verified | `cargo build --release` and `cargo test --release` passed in a containerized Rust toolchain; binary smoke started official `hbbr` and `hbbs` on temporary ports, with `hbbs` TCP/UDP and `hbbr` TCP listeners verified. | Keep this as the official behavior baseline before downstream API integration. |
| Official Docker/s6 base | Partial | `docker/Dockerfile` builds the s6 rootfs image, but runtime healthcheck fails because `/usr/bin/hbbs`, `/usr/bin/hbbr`, and `/usr/bin/rustdesk-utils` are not included by that Dockerfile. | Treat upstream s6 rootfs as packaging input only until a complete binary injection path is defined. |
| Compose-first deployment | Verified | `docker/compose-baseline/` builds a local two-service hbbs/hbbr runtime image from official Stage 1 binaries; compose smoke showed both services healthy, loopback-only published listeners, and generated key material in the named data volume. | Use this as the baseline for adding API service integration in the next stage. |
| Full-s6 integrated image | Verified | `docker/full-s6/` builds a single Debian+s6 image containing `hbbs`, `hbbr`, `rustdesk-api`, and the built `rustdesk-api-web` admin assets. `scripts/smoke-full-s6-image.sh` passed against `rustdesk-server-full-s6:local`, proving s6 PID 1, `hbbr`/`hbbs`/`api` services up, generated server key material, `/_admin/` 200, admin login/current, and `/api/admin/config/server` using the configured loopback API endpoint. | Keep real two-client forced-login/connect validation as a later production gate; do not use this row to claim full RustDesk client compatibility. |
| Forced login (`MUST_LOGIN`) | Partial | `src/rendezvous_server.rs` gates `PunchHoleRequest.token` when `MUST_LOGIN` is enabled, while unit tests prove disabled mode still allows requests and handler-level tests prove missing tokens return `LOGIN_REQUIRED` before peer lookup. Startup now also warns when `MUST_LOGIN=1` but `RUSTDESK_API_JWT_KEY` is empty, avoiding a silent all-token rejection configuration. | Pair this with API-issued tokens and a real RustDesk client/server smoke before marking login connectivity `Verified`. |
| JWT token validation | Partial | Focused tests prove missing, invalid, empty-key, expired, generic HS256, Rust-generated API-shaped `user_id` + `exp`, Go `jwt/v5` generated API-shaped golden token, and live `WeiYusc_rustdesk-api` `/api/login` issued token acceptance using `RUSTDESK_API_JWT_KEY`; `scripts/smoke-api-token.sh` reproduces the live API-issued token gate check without logging token contents. | Verify the same login/token path through a real RustDesk client flow. |
| rustdesk-api config contract | Verified | API fork documents `RUSTDESK_API_RUSTDESK_ID_SERVER`, relay/API/key/key-file, and JWT settings; `scripts/smoke-api-token.sh` runs the compose baseline, launches a temporary SQLite API copy with loopback-only API/server endpoints, calls `/api/login`, decodes API-shaped `user_id` + `exp` claims, and verifies the token against the server gate in an isolated Rust test copy; `scripts/smoke-real-client-register.sh` also proves a real RustDesk Linux client honors preseeded ID/relay/API server config for registration. | Add real two-client login/connect smoke before marking end-to-end forced-login connectivity `Verified`. |
| Real RustDesk client login/connect flow | Partial | `scripts/smoke-real-client-register.sh` downloads or reuses official RustDesk `1.4.8` x86_64 AppImage, runs it under `xvfb-run` with an isolated HOME and loopback config, verifies client logs for `start rendezvous mediator of 127.0.0.1:23116` and `register_pk`, and verifies hbbs logs contain `update_pk`. `scripts/smoke-real-client-connect-probe.sh` additionally starts a real target client and a real `--connect` caller, proving the caller reaches `rendezvous server: 127.0.0.1:23116` and emits `TCP punch attempt`; current same-host AppImage probing stops at `Key mismatch` / hbbs `invalid key`, so it is a boundary probe rather than a successful login/connect smoke. | Still requires a real two-client login/connect on distinct identities or a protocol harness to prove `PunchHoleRequest.token` propagation and `LOGIN_REQUIRED` UX under `MUST_LOGIN=1`. |
| Web Admin frontend | Out-of-scope for server fork | API frontend comes from `rustdesk-api-web`, not this server repository. | Keep server repo docs pointing to API/frontend build inputs; do not vendor frontend here. |
| WebClient/static resources | Deferred/source-sensitive | API fork notes current source snapshot lacks `resources/web`; prior WebClient assets have source/legal sensitivity. | Do not restore or vendor WebClient assets without explicit source/license approval. |
| Official security/hardening PRs | Triage-needed | Official open PRs/issues include hbb_common security update and hardening discussions. | Stage 1/2 issue triage should decide whether to wait, port, or defer. |
| Old fork issues/PRs | Triage-needed | Old fork has token/login/pub-key/update/close-wait issues and PRs such as token verify and `MUST_LOGIN_PEER`. | Compare each against official base and paired API needs before implementation. |

## Issue and PR Triage Seed

| Source | Item | Initial classification | Notes |
|---|---|---|---|
| official | `#666` update hbb_common security | No local action | Open issue asks for latest `hbb_common`; current upstream `master` and this worktree both point at `libs/hbb_common` `83419b6...`, so there is no newer official submodule target visible from `rustdesk/rustdesk-server` to port in this slice. Re-check only when upstream moves the submodule. |
| official | `#653` Docker bind mount writes client-style config | Relevant / compose mitigated | The issue concerns hbbs creating client-style config under a bind-mounted server data dir via shared `hbb_common` config paths. The compose-first baseline mounts `/data`, not `/root`, and smokes verify generated key material in the named data volume; keep monitoring before full-s6/bind-mount packaging. |
| official | PR `#642` hardening hbbs/hbbr | Relevant / do not cherry-pick yet | Open PR proposes broad unauthenticated-abuse hardening plus protocol changes in `hbb_common`. Treat as a security-design input for a later review slice; do not mix with the current minimal `MUST_LOGIN` token gate without protocol/client compatibility review. |
| official | PR `#425` s6 run as user | Packaging hardening follow-up | Open draft PR for official s6 unprivileged runtime. The current full-s6 MVP still runs as root like the inherited upstream s6 pattern; evaluate unprivileged runtime as a later hardening slice after preserving smoke coverage. |
| old fork `lejianwen/rustdesk-server` | `#52` login drops after a week | API token-expiry config / no server fix yet | Open issue shows `RUSTDESK_API_JWT_EXPIRE_DURATION` defaults to one week in the paired API deployment. Current server correctly rejects expired JWTs in tests; next action belongs in API/config docs or a real token-renewal flow, not blind server changes. |
| old fork `lejianwen/rustdesk-server` | `#45` pub key change breaks logged-in clients | Runtime evidence needed | Open issue involves s6 deployment, changed public key, and logged-in client connection failure. Current compose baseline regenerates hbbs key material cleanly, but no real logged-in two-client flow is verified on this host; keep as a later distinct-client/key-rotation smoke gate. |
| old fork `lejianwen/rustdesk-server` | `#47` update server version | Already addressed by base choice | The modernization base is current official `rustdesk/rustdesk-server` `master` (`815c728`), while old fork `forapi` is behind. Treat this as the reason for rebasing onto official, not a separate patch. |
| old fork `lejianwen/rustdesk-server` | PR `#38` token verify | Covered narrowly | Open PR targeted old fork token verification for API issues. Current implementation validates HS256 JWT `exp`, accepts paired API-shaped `user_id` tokens, rejects expired/missing/invalid tokens, and has live API-issued token smoke; do not copy old PR code. |
| old fork `lejianwen/rustdesk-server` | PR `#36` `MUST_LOGIN_PEER` | Deferred product behavior | Open PR adds unauthenticated peer-side bypass while keeping controller auth. This changes auth semantics and remains deferred until basic forced-login client UX/token propagation is verified with distinct clients or a protocol harness. |
| old fork `lejianwen/rustdesk-server` | PR `#51` tcp close-wait | Superseded by base / monitor | Open PR cleans old fork `ws_map`; current official-base source has no matching `ws_map`, so there is no direct patch target. Revisit only if current-base websocket/relay smokes reproduce fd/CLOSE_WAIT leakage. |

## Stage Gates

### Stage 0 Gate

- Fork exists and tracks official `master`.
- Baseline commit, remotes, license, submodule state, and deployment strategy are documented.
- `compatibility.md` exists and uses labels consistently.
- No Rust source or Docker runtime behavior changed.
- `git diff --check` passes.

### Stage 1 Gate

- Submodules initialized at recorded commits.
- Official base builds or build blocker is documented with exact output.
- hbbs/hbbr run under the official Docker/s6 or binary smoke.
- Compose-first runtime assumptions are documented but API integration remains disabled.

### Stage 2 Gate

- Basic forced-login/token behavior is introduced using tests-first workflow.
- `MUST_LOGIN` off preserves official behavior.
- Missing/invalid token failures and valid token path are proven by focused tests.
- Claims remain `Partial` until real RustDesk client/API smoke passes.

### Stage 3 Gate

- Compose-first stack runs hbbs/hbbr and paired API with sanitized configuration.
- Healthchecks cover server and API processes.
- Data dirs, logs, key material, env vars, and upgrade path are documented.

### Stage 4 Gate

- Full-s6 integrated image builds locally from the server, API, and API-web inputs.
- Single-container smoke verifies `hbbr`, `hbbs`, `api`, generated key material, `/_admin/`, admin login/current, and `/api/admin/config/server`.
- Build and smoke scripts leave the paired API/API-web source checkouts clean.
- Image is explicitly local-only until a registry publication workflow is added and verified.

## Non-Goals

- Do not implement features before their stage evidence and approval are complete.
- Do not publish Docker Hub/GHCR images until tag strategy, registry credentials, source/license notes, and release workflow are reviewed.
- Do not vendor `rustdesk-api-web` source or WebClient resources into this server fork; the full-s6 build consumes API-web as an external build input and copies only built admin assets into the image build context.
- Do not copy AGPL reference project UI/source/text/assets without an explicit license decision.
- Do not claim real client compatibility without real RustDesk client/server/API smoke.
