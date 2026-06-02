# MailHog Extension Task

Demonstrate SES email inspection using MailHog extension.

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

1. Confirm the MailHog extension is reachable. `make start` sets
   `EXTENSION_AUTO_INSTALL=localstack-extension-mailhog`, so it auto-installs
   on first boot.

```bash
curl -s -o /dev/null -w "mailhog %{http_code}\n" http://mailhog.localhost.localstack.cloud:4566/
```

If this returns 500 or 404, the extension is still installing in the
background — give it ~30s and retry. If it stays broken, restart with
`localstack stop && make start`.

2. Get API Gateway endpoint:
```bash
API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='QuizAPI'].id" --output text)
API="http://localhost:4566/_aws/execute-api/$API_ID/prod"
```

3. Submit quiz with Email field populated to trigger SendEmailStateMachine.

Options:
- Submit via CloudFront UI
- Get QuizID: `awslocal dynamodb scan --table-name Quizzes`
- Sandbox fallback: `awslocal lambda invoke --function-name SubmitQuizFunction` with email in payload

4. View email in MailHog:
http://mailhog.localhost.localstack.cloud:4566

Headless fallback:
```bash
curl -s http://localhost.localstack.cloud:4566/_aws/ses | jq
```

5. Successful demo shows message with subject "Your Quiz Score".

## How It Works
MailHog extension intercepts LocalStack SES calls and provides inspectable inbox UI.
