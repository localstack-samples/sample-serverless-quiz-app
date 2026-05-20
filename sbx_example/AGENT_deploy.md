# Deploy Task

**Goal:** Get the Serverless Quiz App deployed on LocalStack via the AWS CLI
path (`bin/deploy.sh`) so the user can interact with it in a browser. The
user will follow up by asking the agent to run the automated tests.

This is a **live demo**: a human is watching the agent work via the
browser-embedded tmux viewer at `http://127.0.0.1:7681`. Keep that in mind —
the viewer is not optional support tooling, it's the audience's window.

**Do not use `localstack pod load`.** The Cloud Pod path is intentionally
excluded. Always deploy via `bin/deploy.sh`.

## Steps

0. Source the sandbox persistent environment so installed CLIs are on PATH:
```bash
[ -r /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh
```
Run the idempotent preflight script. Always run it at the start of a
session, regardless of what previous sessions did. It installs apt
packages, creates `$HOME/.venv`, installs `localstack` / `awslocal` /
`aws` / pytest / project deps into it, and persists `$HOME/.venv/bin`
on `PATH` via `/etc/sandbox-persistent.sh` — so no venv activation is
needed in later steps. See AGENT_preflight.md for details.

**STOP — Before any other step:** ALWAYS make sure the demo terminal is
running and explicitly confirm with the user that they can view its output.
If the user cannot see the demo stream, they will miss the demo entirely. Do
not proceed past this gate.

```bash
sbx_example/demo-terminal.sh --bg
curl -sf -o /dev/null -w "ttyd %{http_code}\n" http://127.0.0.1:7681/
```

If port 7681 isn't reachable from the user's host browser, ask them to run on
their host: `sbx ports <sandbox-name> --publish 7681:7681/tcp`. Then **ask
the user to confirm** they see the two panes and wait for confirmation.

1. Run the idempotent preflight script. Always run it at the start of a
   session, regardless of what previous sessions did. It installs apt
   packages, creates `$HOME/.venv`, installs `localstack` / `awslocal` /
   `aws` / pytest / project deps into it, and persists `$HOME/.venv/bin`
   on `PATH` via `/etc/sandbox-persistent.sh` — so no venv activation is
   needed in later steps. See AGENT_preflight.md for details.

```bash
bash sbx_example/preflight.sh
```

If it exits non-zero (e.g. `LOCALSTACK_AUTH_TOKEN` missing), surface the
message to the user and stop — do not try to work around it.

2. Bring up a clean LocalStack instance. `bin/deploy.sh` is NOT idempotent
   (it `set -e`s on the first `ResourceInUseException`), so any residual
   state from previous runs will break it. Always wipe the persistence
   volume before deploying:

```bash
localstack stop || true
sudo rm -rf /home/agent/.cache/localstack/volume/*
make start            # uses LocalStack extensions (mailhog, event-studio)
localstack wait -t 120
```

3. Deploy the app via the AWS CLI script — the canonical path per the
   repo's root `README.md` ("Option 1: AWS CLI Deployment (Recommended)"):

```bash
bash bin/deploy.sh
```

This takes ~2–3 minutes. The script prints CloudFront and API Gateway URLs
on success:

```
CloudFront URL: https://<id>.cloudfront.localhost.localstack.cloud
API Gateway Endpoint: http://localhost:4566/_aws/execute-api/<id>/prod
```

The script ends by running `bin/seed.sh` to populate sample quiz data.
Seed-step errors are non-fatal; the deploy itself is successful as long as
the two URLs are printed.

**Sandbox limitation (important):** In a nested-Docker sandbox (the
`sbx run` environment used for live demos), LocalStack Lambda functions
frequently time out on cold start with:

```
ServiceException: Timeout while starting up lambda environment
```

This causes `bin/seed.sh` to fail with `HTTP 502 - Internal server error`
on every `createquiz` / `submitquiz` call, each request taking ~90s before
giving up. If you see this, **do not wait for seed to finish** — stop the
script (the deploy itself already succeeded by this point) and proceed. The
quiz tables will be empty, and the user can either:

- Use the frontend UI to create quizzes manually (Lambdas often warm up
  after a few minutes of activity), or
- Skip seeding for this demo; the infrastructure resources are all in place.

```bash
# Stop a stuck seed if needed:
pkill -f "bin/seed.sh"; pkill -f "curl.*createquiz\|curl.*submitquiz"
```

4. Verify the deploy:

```bash
awslocal lambda list-functions --query 'Functions[].FunctionName' --output text
awslocal apigateway get-rest-apis --query "items[?name=='QuizAPI'].id" --output text
awslocal dynamodb scan --table-name Quizzes --select COUNT --query 'Count' --output text
```

Expect 8 Lambdas and a `QuizAPI` ID. Quiz count may be 0 if seeding was
skipped or 502'd (see the sandbox limitation above) — that's still a
successful deploy.

5. Check the LocalStack extensions used by later demos:

```bash
curl -s -o /dev/null -w "event-studio %{http_code}\n" http://eventstudio.localhost.localstack.cloud:4566/
curl -s -o /dev/null -w "mailhog      %{http_code}\n" http://mailhog.localhost.localstack.cloud:4566/
```

Both should return 200. If 500/404, restart with `localstack stop && make start`.

6. Print the URLs the user needs:

- **CloudFront app URL** (from step 3 output) — the user opens this in their
  browser to interact with the quiz app. Requires `sbx ports <sandbox> --publish 4566:4566/tcp`
  on the host.
- Resource Browser: https://app.localstack.cloud/inst/default/resources
- Policy Stream: https://app.localstack.cloud/inst/default/policy-stream
- Chaos Engineering: https://app.localstack.cloud/inst/default/chaos-engineering
- Event Studio: http://eventstudio.localhost.localstack.cloud:4566/
- MailHog: http://mailhog.localhost.localstack.cloud:4566/
