# Deploy Task

**Goal:** Get the Serverless Quiz App deployed on LocalStack via the AWS CLI
path (`bin/deploy.sh`) so the user can interact with it in a browser. The
user will follow up by asking the agent to run the automated tests.

This is a **live demo**: a human is watching the agent work via the
browser-embedded tmux viewer at `http://127.0.0.1:7681`. Keep that in mind —
the viewer is not optional support tooling, it's the audience's window.

**Do not use Cloud Pods.** The Cloud Pod path is intentionally excluded.
Always deploy via `bin/deploy.sh`.

## Steps

0. Source the sandbox persistent environment so installed CLIs are on PATH:
```bash
[ -r /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh
```

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
   packages, `lstk` (LocalStack CLI v2, via npm), AWS CLI v2, an `awslocal`
   shim that proxies through `lstk aws`, and a small Python venv at
   `$HOME/.venv` for test dependencies (boto3, pytest, requests,
   localstack-sdk-python). It persists `$HOME/.venv/bin` on `PATH` and adds
   `.localstack.cloud` to `NO_PROXY` via `/etc/sandbox-persistent.sh` — so
   no venv activation is needed in later steps. See AGENT_preflight.md for
   details.

```bash
bash sbx_example/preflight.sh
```

If it exits non-zero (e.g. `LOCALSTACK_AUTH_TOKEN` missing), surface the
message to the user and stop — do not try to work around it.

2. Bring up a clean LocalStack instance. `bin/deploy.sh` is NOT idempotent
   (it `set -e`s on the first `ResourceInUseException`), so any residual
   state from previous runs will break it. Always wipe the volume before
   deploying. `lstk` reads `.lstk/config.toml` in this repo, which sets
   `EXTENSION_AUTO_INSTALL` to pull in `event-studio` and `mailhog`:

```bash
lstk stop || true
lstk volume clear --force || true
make start            # runs `lstk start --non-interactive`; picks up .lstk/config.toml
```

`lstk start` blocks until the container is healthy on `:4566` — no separate
wait step is needed. Extensions install in the background; they take an
extra ~30s after the gateway is ready.

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

`bin/deploy.sh` uses `awslocal` for ~50 AWS calls. The `awslocal` shim
installed by preflight proxies through `lstk aws`, which adds ~0.1s per call.

The script auto-detects the host architecture (`uname -m`) and passes
`--architectures arm64` (or `x86_64`) to every `create-function` call. This
matters: a wrong-arch Lambda runtime image fails with `exec format error`
and every invocation hangs for ~90s before LocalStack gives up. The deploy
+ seed cycle goes from ~22 minutes (every seed call timing out) to ~70s
when the arch matches.

The script ends by running `bin/seed.sh` to populate sample quiz data.
With the arch fix, seeding completes in a couple of seconds. Expect:

- 3 quizzes in DynamoDB `Quizzes` (Comic, AWS, Star Wars)
- 9 submissions in `UserSubmissions` (scored asynchronously by the
  `ScoringFunction` Lambda via SQS)

4. Verify the deploy:

```bash
awslocal lambda list-functions --query 'Functions[].FunctionName' --output text
awslocal apigateway get-rest-apis --query "items[?name=='QuizAPI'].id" --output text
awslocal dynamodb scan --table-name Quizzes --select COUNT --query 'Count' --output text
```

Expect 8 Lambdas, a `QuizAPI` ID, and 3 quizzes (post-seed). If quiz count
is 0, seed probably failed — re-run `bash bin/seed.sh` once and re-check.

5. Check the LocalStack extensions used by later demos:

```bash
curl -s -o /dev/null -w "event-studio %{http_code}\n" http://eventstudio.localhost.localstack.cloud:4566/
curl -s -o /dev/null -w "mailhog      %{http_code}\n" http://mailhog.localhost.localstack.cloud:4566/
```

Both should return 200. If 500/404, the extensions may still be installing
in the background (give it another 20s and retry) or the container missed
the auto-install env var — restart with `lstk stop && make start`.

6. Print the URLs the user needs:

- **CloudFront app URL** (from step 3 output) — the user opens this in their
  browser to interact with the quiz app. Requires `sbx ports <sandbox> --publish 4566:4566/tcp`
  on the host.
- Resource Browser: https://app.localstack.cloud/inst/default/resources
- Policy Stream: https://app.localstack.cloud/inst/default/policy-stream
- Chaos Engineering: https://app.localstack.cloud/inst/default/chaos-engineering
- Event Studio: http://eventstudio.localhost.localstack.cloud:4566/
- MailHog: http://mailhog.localhost.localstack.cloud:4566/
