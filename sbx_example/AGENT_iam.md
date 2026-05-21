# IAM Policy Stream Task

Demonstrate IAM policy debugging using intentionally broken policy.

This is a **live demo**: a human is watching the agent work via the
browser-embedded tmux viewer at `http://127.0.0.1:7681`. Treat that viewer
as the audience's window — not optional support tooling.

## Requirements
- Stack deployed (see AGENT_deploy.md)

## Steps

0. Source the sandbox persistent environment:
```bash
[ -r /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh
```

**STOP — Before any other step:** ALWAYS make sure the demo terminal is
running and explicitly confirm with the user that they can view its output.
If the user cannot see the demo stream, they will miss the demo entirely.
Do not proceed past this gate.

```bash
sbx_example/demo-terminal.sh --bg
curl -sf -o /dev/null -w "ttyd %{http_code}\n" http://127.0.0.1:7681/
```

If port 7681 isn't reachable, ask the user to run on their host:
`sbx ports <sandbox-name> --publish 7681:7681/tcp`. Then **ask the user to
confirm** they see the two panes and wait for confirmation.

1. Have user open Policy Stream and click "Enable Stream", uncheck "Show internal calls":
https://app.localstack.cloud/inst/default/policy-stream

2. Show intentionally broken policy at `configurations/submit_quiz_policy.json`.
Missing permissions: `sqs:GetQueueUrl`, `sqs:SendMessage` on QuizSubmissionQueue.

Compare with deployed policy:
```bash
awslocal iam get-policy-version \
  --policy-arn arn:aws:iam::000000000000:policy/SubmitQuizFunctionPolicy \
  --version-id v1 --query 'PolicyVersion.Document'
```

3. Note: `ENFORCE_IAM` is startup-only env var. Policy Stream records calls without enforcement. For strict enforcement demo, add `LOCALSTACK_ENFORCE_IAM=1` to docker-compose.yml and restart.

4. Trigger violation:
- Preferred: Submit quiz from CloudFront UI or POST to /submitquiz
- Direct invoke (also fine):
```bash
awslocal lambda invoke --function-name SubmitQuizFunction \
  --payload '{"body":"{\"QuizID\":\"<id>\",\"Answers\":[0]}"}' \
  /tmp/out.json && cat /tmp/out.json
```

Get QuizID from: `awslocal dynamodb scan --table-name Quizzes --query 'Items[].QuizID.S' --output text`

5. Inspect denial in CloudWatch:
```bash
awslocal logs tail /aws/lambda/SubmitQuizFunction --since 5m
```

6. Patch policy by creating new version with missing statement:
```bash
cat > /tmp/fixed_policy.json <<'JSON'
{"Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":"dynamodb:GetItem",
   "Resource":"arn:aws:dynamodb:us-east-1:000000000000:table/Quizzes"},
  {"Effect":"Allow",
   "Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],
   "Resource":["arn:aws:logs:us-east-1:000000000000:log-group:/aws/lambda/SubmitQuizFunction:*",
               "arn:aws:logs:us-east-1:000000000000:log-group:/aws/lambda/SubmitQuizFunction:log-stream:*"]},
  {"Effect":"Allow","Action":["sqs:GetQueueUrl","sqs:SendMessage"],
   "Resource":"arn:aws:sqs:us-east-1:000000000000:QuizSubmissionQueue"}
]}
JSON

awslocal iam create-policy-version \
  --policy-arn arn:aws:iam::000000000000:policy/SubmitQuizFunctionPolicy \
  --policy-document file:///tmp/fixed_policy.json \
  --set-as-default
```

7. Re-submit quiz and verify SQS path works:
```bash
awslocal sqs get-queue-attributes \
  --queue-url $(awslocal sqs get-queue-url --queue-name QuizSubmissionQueue --query QueueUrl --output text) \
  --attribute-names ApproximateNumberOfMessages
```
