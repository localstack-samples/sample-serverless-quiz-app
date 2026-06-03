# Deploy Task

**Goal:** Get the Serverless Quiz App deployed on LocalStack via CDK
path (`bin/deploy_cdk.sh`) so the user can interact with it in a browser. The
user will follow up by asking the agent to run the automated tests.

This is a **live demo**: a human is watching the agent work via the
browser-embedded tmux viewer at `http://127.0.0.1:7681`. Keep that in mind —
the viewer is not optional support tooling, it's the audience's window.

**Do not use Cloud Pods.** The Cloud Pod path is intentionally excluded.
Always deploy via `bin/deploy_cdk.sh`.

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

1. Run the idempotent preflight script (see `AGENT_preflight.md` and
   https://v2.app.localstack.cloud/agents.md for what it sets up):

```bash
bash sbx_example/preflight.sh
```

If it exits non-zero (e.g. `LOCALSTACK_AUTH_TOKEN` missing), surface the
message to the user and stop — do not try to work around it.

**cdklocal (one-time setup):** Install the CDK and cdklocal CLI wrappers:

```bash
npm install -g aws-cdk-local aws-cdk
```

**LocalStack MCP server (one-time setup):** Install the LocalStack MCP server
so Claude has access to LocalStack-specific tools (resource inspection,
state management, etc.). Run once per sandbox, then restart the Claude session:

```bash
claude mcp add localstack-mcp-server -- npx -y @localstack/localstack-mcp-server
```

`LOCALSTACK_AUTH_TOKEN` is picked up from the environment automatically.
See https://github.com/localstack/localstack-mcp-server#configuration for details.

```bash
localstack stop || true
make start
```

`make start` runs `localstack start -d` then `localstack wait -t 60`,
blocking until the container is healthy on `:4566`. Extensions install in
the background; they take an extra ~30s after the gateway is ready.

3. Deploy the app via the AWS CLI script — the canonical path per the
   repo's root `README.md` ("Option 1: AWS CLI Deployment (Recommended)"):

```bash
bash bin/deploy_cdk.sh
```

This takes ~2–3 minutes. The script prints CloudFront and API Gateway URLs
on success:

```
CloudFront URL: https://<id>.cloudfront.localhost.localstack.cloud
API Gateway Endpoint: http://localhost:4566/_aws/execute-api/<id>/prod
```

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

5. Check the MailHog extension used by later demos:

```bash
curl -s -o /dev/null -w "mailhog %{http_code}\n" http://mailhog.localhost.localstack.cloud:4566/
```

Should return 200. If 500/404, the extension may still be installing
in the background (give it another 20s and retry) or the container missed
the auto-install env var — restart with `localstack stop && make start`.

6. Print the URLs the user needs:

- **CloudFront app URL** (from step 3 output) — the user opens this in their
  browser to interact with the quiz app. Requires `sbx ports <sandbox> --publish 4566:4566/tcp`
  on the host.
- Resource Browser: https://app.localstack.cloud/inst/default/resources
- Policy Stream: https://app.localstack.cloud/inst/default/policy-stream
- Chaos Engineering: https://app.localstack.cloud/inst/default/chaos-engineering
- MailHog: http://mailhog.localhost.localstack.cloud:4566/
