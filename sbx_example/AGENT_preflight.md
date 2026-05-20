# Preflight Task

Verify tools, credentials, and dependencies before running demos.

## Run

```bash
bash sbx_example/preflight.sh
```

That's it. The script is **idempotent** — run it at the start of every
session, regardless of what previous sessions did. It will:

- Install apt packages (`jq`, `make`, `zip`, `git`, `nodejs`, `npm`,
  `python3-venv`, ...).
- Create a Python virtualenv at `$HOME/.venv` (persistent across worktrees).
- Install `localstack`, `awscli`, `awscli-local`, and
  `tests/requirements-dev.txt` (boto3, requests, pytest, localstack-sdk-python)
  into that venv.
- Append `export PATH="$HOME/.venv/bin:$PATH"` to `/etc/sandbox-persistent.sh`
  so every subsequent bash invocation in the sandbox finds the CLIs without
  needing to `source .venv/bin/activate`.
- Install optional npm CLIs (`aws-cdk`, `aws-cdk-local`).
- Write a dummy `~/.aws/credentials` if missing.

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
