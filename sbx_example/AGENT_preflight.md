# Preflight Task

Verify tools, credentials, and dependencies before running demos.

For general LocalStack setup (auth tokens, starting LocalStack, AWS tooling
configuration), see: https://v2.app.localstack.cloud/agents.md

## Run

```bash
bash sbx_example/preflight.sh
```

The script is **idempotent** — run it at the start of every session. It
installs apt packages, AWS CLI v2, a Python venv with `localstack`,
`awslocal`, and the project's test dependencies, and wires everything onto
`PATH` via `/etc/sandbox-persistent.sh`.

## Exit conditions

- **Exit 0**: ready to proceed. All required CLIs are on `PATH`,
  `LOCALSTACK_AUTH_TOKEN` is set.
- **Exit 1**: `LOCALSTACK_AUTH_TOKEN` is missing. Ask the user to set it on
  their host via `sbx secret set <sandbox> localstack-auth-token -t <token>`
  and restart the session. Do not proceed.
