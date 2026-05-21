# Preflight Task

Verify tools, credentials, and dependencies before running demos.

## Run

```bash
bash sbx_example/preflight.sh
```

That's it. The script is **idempotent** — run it at the start of every
session, regardless of what previous sessions did. It will:

- Install apt packages (`jq`, `make`, `zip`, `unzip`, `curl`, `git`,
  `nodejs`, `npm`, `python3-venv`, ...).
- Install `lstk` (LocalStack CLI v2) globally via npm.
- Install AWS CLI v2 from the official binary (no Python wrapper needed).
- Write an `awslocal` shim at `/usr/local/bin/awslocal` that proxies through
  `lstk aws`, so `bin/deploy.sh` and the AGENT_*.md files keep working
  unchanged.
- Append `localhost.localstack.cloud,.localstack.cloud` to `NO_PROXY` in
  `/etc/sandbox-persistent.sh` so `lstk aws` can reach the local emulator
  inside sandboxes that have an HTTPS proxy.
- Seed `~/.aws/config` and `~/.aws/credentials` with a `localstack` profile
  pointing at `http://localhost:4566` (skips needing to run the interactive
  `lstk setup aws`).
- Create a Python virtualenv at `$HOME/.venv` **just for test
  dependencies** — `boto3`, `pytest`, `requests`, `localstack-sdk-python` —
  and install `tests/requirements-dev.txt` into it. The LocalStack CLI
  itself no longer lives in this venv.
- Append `export PATH="$HOME/.venv/bin:$PATH"` to
  `/etc/sandbox-persistent.sh` so subsequent bash invocations find `pytest`
  without needing to `source .venv/bin/activate`.

## Exit conditions

- **Exit 0**: ready to proceed. All required CLIs are on `PATH`,
  `LOCALSTACK_AUTH_TOKEN` is set.
- **Exit 1**: `LOCALSTACK_AUTH_TOKEN` is missing. Ask the user to set it on
  their host via `sbx secret set <sandbox> localstack-auth-token -t <token>`
  and restart the session. Do not proceed.

## When to re-run

- After `sbx run` creates a fresh sandbox.
- If a CLI you expect is missing (rare — usually means the apt cache moved
  or the venv was deleted).
- Never just to "be safe" mid-session — it's idempotent but takes ~30s.
