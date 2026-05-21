# Migration: legacy `localstack` CLI → `lstk` (LocalStack CLI v2)

This doc records every change made when migrating the demo from the Python
`localstack` CLI to the new Go-based [`lstk`](https://github.com/localstack/lstk)
client (npm package `@localstack/lstk`, v0.8.0 at time of writing).

## Why migrate

- Single binary install via `npm i -g @localstack/lstk` (or `brew`, or a
  GitHub release) — no Python venv, no pip dependency hell.
- TTY-aware: shows a Bubble Tea TUI when run interactively, falls back to
  plain output when piped or in CI (`--non-interactive`).
- Built-in `lstk aws` proxy with auto-configured profile.
- The previous demo's preflight had to install a Python venv just to get
  the legacy CLI on `PATH`; that's now ~5 fewer steps.

## What `lstk` does NOT have (still needs the legacy `localstack` CLI, OR a workaround)

| Legacy command                       | Replacement used in this demo                                                                  |
|--------------------------------------|------------------------------------------------------------------------------------------------|
| `localstack wait -t 120`             | `lstk start --non-interactive` already blocks until healthy; for explicit waits we use a `curl http://localhost:4566/_localstack/health` loop |
| `localstack pod load <name>`         | The demo intentionally avoids Cloud Pods (`bin/deploy.sh` is the canonical path) — no replacement needed |
| `localstack extensions install <ext>`| Set `EXTENSION_AUTO_INSTALL` via the per-repo `.lstk/config.toml` (`[env.demo]` section) and reference it from `[[containers]]` `env = ["demo"]` |
| `localstack auth set-token <token>`  | `lstk login` (interactive only — TTY required) **or** the existing `LOCALSTACK_AUTH_TOKEN` env var, which `lstk` propagates to the container. The sandbox demo keeps using the env var via `/etc/sandbox-persistent.sh`. |

## Command map (what we did use)

| Was                                   | Now                                                                |
|---------------------------------------|--------------------------------------------------------------------|
| `localstack start -d`                 | `lstk start --non-interactive`                                     |
| `localstack stop`                     | `lstk stop`                                                        |
| `localstack restart`                  | `lstk restart`                                                     |
| `localstack wait -t 120`              | `lstk start` blocks until healthy; otherwise `curl /_localstack/health` loop |
| `localstack logs`                     | `lstk logs --follow`                                               |
| `localstack state export app.zip`     | `lstk snapshot save app.zip`                                       |
| `localstack state import app.zip`     | _no direct equivalent yet_ (removed `load-state` Makefile target)  |
| `sudo rm -rf ~/.cache/localstack/volume/*` | `lstk volume clear --force`                                    |
| `pip install awscli awscli-local`     | AWS CLI v2 binary install + `awslocal` shim → `exec lstk aws "$@"` |

## Container name change (broke demo-terminal.sh)

The legacy CLI named its container **`localstack-main`**. `lstk` names it
**`localstack-aws`**. The browser-embedded tmux viewer (`demo-terminal.sh`)
was hard-coded to `docker logs -f localstack-main`, so it sat on
"waiting for localstack-main…" forever after the migration.

**Fix:** updated `demo-terminal.sh` and `pre-demo-check.sh` to look for
`localstack-aws`.

## Proxy gotcha (the one nasty surprise)

Inside an `sbx` sandbox, all outbound HTTP/HTTPS traffic is forced through
a proxy at `gateway.docker.internal:3128` via these env vars:

```
HTTP_PROXY=http://gateway.docker.internal:3128
HTTPS_PROXY=http://gateway.docker.internal:3128
NO_PROXY=localhost,127.0.0.1,::1,gateway.docker.internal
```

`lstk aws` (Go HTTP client) honors `NO_PROXY`, but the URLs it targets are
the LocalStack hostname variants (e.g. `localhost.localstack.cloud`), which
**aren't covered by the default `NO_PROXY` list.** The result: every
`awslocal` call routed through `lstk aws` failed with:

```
b'dial tcp 127.0.0.1:4566: connect: connection refused\n'
```

The proxy was trying to dial `127.0.0.1:4566` from *its own* network namespace,
not the sandbox's.

**Fix:** preflight appends `localhost.localstack.cloud,.localstack.cloud` to
`NO_PROXY` in `/etc/sandbox-persistent.sh`. Verified by running
`unset HTTP{,S}_PROXY` before `lstk aws` — once the proxy is out of the
picture, it works fine.

## `lstk setup aws` is interactive-only

`lstk setup aws` writes the `localstack` AWS profile to `~/.aws/config` +
`~/.aws/credentials`, but it requires a TTY and refuses to run in scripts:

```
Error: setup aws requires an interactive terminal
```

**Fix:** preflight writes the profile manually (it's just a few INI lines).
This matches what `lstk setup aws` would generate.

## Files changed

### `sbx_example/preflight.sh` — full rewrite
- Dropped: `pip install localstack awscli awscli-local` (the old Python CLI path).
- Added: `npm install -g @localstack/lstk`.
- Added: AWS CLI v2 binary install (arch-detected; `x86_64` and `aarch64`).
- Added: `/usr/local/bin/awslocal` shim — `exec lstk aws "$@"`.
- Added: NO_PROXY append for `*.localstack.cloud`.
- Added: `~/.aws/{config,credentials}` write with the `localstack` profile.
- Kept: a Python venv at `$HOME/.venv`, **only** for test deps
  (`boto3`, `pytest`, `requests`, `localstack-sdk-python`). Tests + the
  chaos SDK need `boto3` to be importable.

### `.lstk/config.toml` — new file
- Per-project `lstk` config. Sets `EXTENSION_AUTO_INSTALL` for `event-studio`
  and `mailhog` via a named env profile, so `make start` (which calls
  `lstk start --non-interactive` from the repo root) auto-loads them.

### `Makefile`
- `start`: `localstack start -d` → `lstk start --non-interactive`.
- `stop`:  `localstack stop` → `lstk stop`.
- `ready`: `localstack wait -t 30` → `curl /_localstack/health` poll loop.
- `logs`:  `localstack logs` → `lstk logs`.
- `save-state`: `localstack state export` → `lstk snapshot save`.
- `load-state`: removed — no `lstk` equivalent yet.

### `sbx_example/AGENT_deploy.md`
- Updated step 2 to use `lstk stop`, `lstk volume clear --force`, removed
  the explicit `localstack wait -t 120` (lstk start blocks until healthy).
- Updated step 5 wording: extensions auto-install via `.lstk/config.toml`,
  may need ~30s after gateway-ready to settle.

### `sbx_example/AGENT_preflight.md`
- Rewrote intro to describe the new tool stack: lstk, AWS CLI v2,
  `awslocal` shim, test-deps venv.

### `sbx_example/AGENT_mail.md`
- Removed `localstack extensions install/list` (lstk has no extensions
  subcommand). Replaced with a `curl` health check; relies on the
  `.lstk/config.toml` auto-install.

### `sbx_example/AGENT_chaos.md`
- Removed the bogus `/opt/localstack-venv/bin/pip install ...` line.
  `localstack-sdk-python` is installed by preflight via
  `tests/requirements-dev.txt`.

### `sbx_example/README.md`
- Mention `lstk` install + that the legacy `localstack` CLI is no longer
  required.
- Updated troubleshooting: container name changed (`localstack-main` →
  `localstack-aws`), added the `lstk aws` NO_PROXY gotcha.
- Teardown: `lstk stop` instead of `localstack stop`.

### `sbx_example/demo-terminal.sh`
- Container name in the `docker logs -f` watcher: `localstack-main` →
  `localstack-aws`.

### `sbx_example/pre-demo-check.sh`
- Tool check list: `localstack` → `lstk`, plus `aws`.
- Container name: `localstack-main` → `localstack-aws`.
- Warmup: dropped the separate `localstack wait` step (lstk start is sync).

### `sbx_example/docker-agent.yaml`
- Teardown command and "known issues" copy updated.

## Performance

Single `awslocal sts get-caller-identity` call:

| Path                              | Time   |
|-----------------------------------|--------|
| Plain `aws --endpoint-url=...`    | ~0.28s |
| `awslocal` shim → `lstk aws`      | ~0.42s |

About 50% per-call overhead. Over the ~50 calls in `bin/deploy.sh` that's
~7s extra wall time, acceptable. If that's ever problematic, swap the shim
to `exec aws --endpoint-url=http://localhost:4566 "$@"` directly.

## End-to-end startup timings (sandbox, ARM64)

- `npm install -g @localstack/lstk`: ~2s.
- AWS CLI v2 binary install: ~5s.
- `lstk start --non-interactive` (image already pulled): ~7s to healthy.
- Extensions auto-install in background: ~30–60s after healthy.
- `bin/deploy.sh` (incl. seed): ~70s once the Lambda arch fix below is in.
  Previously ~22 minutes because every seed call timed out.

## Lambda architecture fix (the real reason seed was hanging)

Symptom in the old AGENT_deploy.md: "every `createquiz` / `submitquiz` call
returns 502 after ~90s, **do not wait for seed to finish**." The doc framed
it as a sandbox limitation we had to live with. It isn't — it's a
one-character bug.

The lambda runtime container was logging:

```
fork/exec /var/runtime/bootstrap: exec format error
Runtime init failed to initialize: InitDoneFailed. Exiting.
```

The sandbox host is `aarch64` but `awslocal lambda create-function` defaults
to `x86_64`. LocalStack pulls the wrong runtime image
(`public.ecr.aws/lambda/python:3.10` — no arch suffix is `linux/amd64`),
the bootstrap binary inside it is x86_64, and the kernel refuses to exec
it. LocalStack waits for the runtime to come up, never sees it, and
eventually returns `ServiceException: Timeout while starting up lambda
environment` after `LAMBDA_RUNTIME_ENVIRONMENT_TIMEOUT` (default 20s).
boto3 retries 2–3 times, each retry takes 20s, total ~90s.

**Fix:** `bin/deploy.sh` now does:

```bash
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    aarch64|arm64) LAMBDA_ARCH="arm64" ;;
    x86_64|amd64)  LAMBDA_ARCH="x86_64" ;;
esac
```

…and passes `--architectures ${LAMBDA_ARCH}` to every `create-function`
call. After this change:

| Operation                       | Before fix              | After fix |
|---------------------------------|-------------------------|-----------|
| Direct `lambda invoke` (cold)   | 60s, then ServiceException | 0.9s   |
| Direct `lambda invoke` (warm)   | 60s, then ServiceException | 0.5s   |
| API GW → Lambda → DynamoDB      | 90s timeout → HTTP 502    | 30ms   |
| `bin/seed.sh` (3 quizzes + 9 submissions) | 20+ minutes, all failing | <2s, all OK |

We also bumped `LAMBDA_RUNTIME_ENVIRONMENT_TIMEOUT=120` and added
`LAMBDA_KEEPALIVE_MS=900000` in `.lstk/config.toml`. Strictly speaking
neither is required once the arch is correct (cold start is sub-second),
but the longer timeout is cheap insurance for slow first-time runtime
image pulls in fresh sandboxes, and the keepalive avoids re-cold-starting
between demos.

## Verification checklist

1. `bash sbx_example/preflight.sh` → exit 0, all tools `OK`.
2. `make start` → container `localstack-aws` healthy on `:4566`.
3. `awslocal dynamodb list-tables` → empty list (proves the
   shim → `lstk aws` → real `aws` chain works).
4. `bash bin/deploy.sh` → prints CloudFront + API Gateway URLs in ~70s,
   including seed.
5. `awslocal dynamodb scan --table-name Quizzes --select COUNT` → 3.
6. `awslocal dynamodb scan --table-name UserSubmissions --select COUNT` → 9.
7. `curl http://mailhog.localhost.localstack.cloud:4566/` → 200 (after
   extensions settle).

## Open issues / future work

- `lstk` has no `pod load` / `pod save`. If we ever bring Cloud Pods back
  into the demo, we'll need to keep the legacy CLI alongside (or hit the
  Cloud Pods HTTP API directly).
- `lstk setup aws` needs a non-interactive flag; until then, preflight
  writes the profile by hand.
- The `awslocal` → `lstk aws` indirection requires the real `aws` CLI to
  be installed. If `lstk aws` ever ships its own AWS SDK transport, we
  could drop the AWS CLI install.
- LocalStack extensions (event-studio, mailhog) return 500 from the
  gateway when curl'd via DNS (`mailhog.localhost.localstack.cloud:4566`)
  in some sandbox environments — appears to be an internal proxy issue
  inside LocalStack, not a regression from this migration. Path-based
  access (`/_extension/mailhog/`) works.
