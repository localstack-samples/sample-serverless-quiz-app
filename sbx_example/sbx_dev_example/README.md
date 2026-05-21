# sbx_dev_example — agent extends the quiz app without knowing it's LocalStack

This is the **inverse demo** to the other AGENT_*.md runbooks under
`sbx_example/`. Those scripts walk a guide agent through a known set of
steps. This one drops a fresh agent into the repo with a task that *looks
like real AWS engineering work*, and we watch them figure it out —
discovering the deployed infrastructure, deciding on IAM, writing code,
deploying, and verifying.

The trick: the agent doesn't know the AWS endpoint they're hitting is
LocalStack. As far as they can tell from `aws sts get-caller-identity`
and friends, it's just an AWS sub-account. That's the point — they
develop and deploy as if it were real AWS, and the bug they ship would
be the bug they ship in prod.

## Pre-requisites

1. The main quiz app must already be deployed. Run the normal flow
   first:
   ```bash
   bash sbx_example/preflight.sh
   bash sbx_example/AGENT_deploy.md   # or just `make start && bin/deploy.sh`
   ```
2. The `awslocal` shim from preflight must be on PATH (it routes
   through `lstk aws`). The new agent will use `aws`, not `awslocal` —
   the next step makes that work.

## Setup: make `aws` transparently hit LocalStack

The agent will type `aws ...` everywhere. We need `aws` to land on the
LocalStack gateway without the agent realizing. One env var does it
(the AWS SDK + CLI both honor `AWS_ENDPOINT_URL`):

```bash
sudo tee -a /etc/sandbox-persistent.sh >/dev/null <<'EOF'
# Route plain `aws` and boto3 at the platform's emulator gateway.
# Set explicitly so engineers don't have to remember --endpoint-url.
export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"
EOF
```

Or, for a single session without persisting:

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_REGION=us-east-1
```

After this, `aws sts get-caller-identity` returns `arn:aws:iam::000000000000:root`,
which looks like a perfectly ordinary AWS account ID. The agent shouldn't
notice anything off unless they `printenv | grep AWS_`.

## Hand the agent the task

In a fresh sandbox shell:

```bash
sbx exec <sandbox-name> claude "Read sbx_example/sbx_dev_example/AGENT_TASK.md and execute it"
```

Or, if running inside the sandbox already:

```bash
claude "Read sbx_example/sbx_dev_example/AGENT_TASK.md and execute it"
```

The agent's task file (`AGENT_TASK.md`) is written in deliberately
plain "platform team handing this to a contractor" language. Nothing in
it references LocalStack, `lstk`, `awslocal`, or `:4566`. The
`INFRASTRUCTURE.md` companion file is similarly sanitized.

## What good output looks like

When the agent says "done", you should be able to:

```bash
# Their script exists and runs
bash sbx_example/sbx_dev_example/deploy.sh

# A new table exists
aws dynamodb describe-table --table-name QuizAnalytics \
  --query 'Table.TableStatus'

# Streams are enabled on UserSubmissions
aws dynamodb describe-table --table-name UserSubmissions \
  --query 'Table.[StreamSpecification,LatestStreamArn]'

# Their lambda exists, on the right architecture
aws lambda get-function --function-name QuizAnalyticsFunction \
  --query 'Configuration.[State,Architectures,Runtime]'

# It has an event source mapping on the UserSubmissions stream
aws lambda list-event-source-mappings \
  --function-name QuizAnalyticsFunction \
  --query 'EventSourceMappings[].[EventSourceArn,State]'

# Trigger a new submission and watch the row land
API_ID=$(aws apigateway get-rest-apis --query "items[?name=='QuizAPI'].id" --output text)
curl -X POST "http://localhost:4566/_aws/execute-api/$API_ID/prod/submitquiz" \
  -H "Content-Type: application/json" \
  -d '{"Username":"testuser","QuizID":"<existing-quiz-id>","Answers":{"0":{"Answer":"A","TimeTaken":12}}}'

# Wait a few seconds for SQS → ScoringFunction → DDB insert → DDB stream → analytics lambda
sleep 5
aws dynamodb scan --table-name QuizAnalytics --query 'Items[].Username.S'
```

## What's interesting to watch

- **Does the agent enable streams correctly?** `UserSubmissions` is
  created without streams. They need to spot this and run
  `update-table --stream-specification ...`.
- **What architecture do they pick for the lambda?** If they don't
  check `uname -m` and just default to `x86_64`, the lambda will
  hang on invocation (this is the same bug we recently fixed in
  `bin/deploy.sh`). If they read INFRASTRUCTURE.md / the existing
  lambdas closely they'll catch the hint.
- **IAM judgment.** Do they reuse `ScoringRole` (less code, blurs
  separation) or write a new `QuizAnalyticsRole` (more bash, cleaner)?
  Either is defensible — `README.md` asks them to explain.
- **Idempotency.** Their `deploy.sh` should be safe to re-run. Watch
  for `EntityAlreadyExists` / `ResourceInUseException` on the second
  run.

## When you want to reset

Wipe just the analytics-specific resources (leaves the quiz app intact):

```bash
aws lambda delete-event-source-mapping \
  --uuid "$(aws lambda list-event-source-mappings \
    --function-name QuizAnalyticsFunction \
    --query 'EventSourceMappings[0].UUID' --output text)" 2>/dev/null
aws lambda delete-function --function-name QuizAnalyticsFunction 2>/dev/null
aws dynamodb delete-table --table-name QuizAnalytics 2>/dev/null
aws iam delete-role-policy --role-name QuizAnalyticsRole --policy-name QuizAnalyticsPolicy 2>/dev/null
aws iam delete-role --role-name QuizAnalyticsRole 2>/dev/null
# Optionally turn streams back off on UserSubmissions
aws dynamodb update-table --table-name UserSubmissions \
  --stream-specification StreamEnabled=false 2>/dev/null
rm -rf sbx_example/sbx_dev_example/lambda \
       sbx_example/sbx_dev_example/deploy.sh \
       sbx_example/sbx_dev_example/*.json
```

For a fully clean restart, just nuke the sandbox: `sbx rm <sandbox-name>`.

## Files in this directory

- `AGENT_TASK.md` — the task prompt. **Do not edit during a demo.**
  Sanitized of LocalStack references.
- `INFRASTRUCTURE.md` — companion ref the task points at. Same
  sanitization. Updated whenever `bin/deploy.sh` changes the shape of
  the quiz app.
- `README.md` (this file) — the meta-doc. For you, not for the agent.
  Do not point the agent at this file.
- `setup_env.sh` — exports the platform's default AWS endpoint + region
  so the agent's plain `aws` and boto3 calls land on the shared gateway
  without the agent thinking about it. Optional; you can also bake the
  exports into `/etc/sandbox-persistent.sh` (see "Setup" above).
- _(post-agent-run)_ `lambda/`, `deploy.sh`, and probably a few JSON
  policy files. These are whatever the agent produced. Inspect, then
  decide if they're worth committing as a reference implementation.
