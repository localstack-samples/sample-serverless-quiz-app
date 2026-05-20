# Chaos Engineering Task

Demonstrate DynamoDB outage resilience using LocalStack Chaos Engineering.

This is a **live demo**: a human is watching the agent work via the
browser-embedded tmux viewer at `http://127.0.0.1:7681`. Treat that viewer
as the audience's window — not optional support tooling.

## Requirements
- LocalStack Enterprise license
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

1. Verify stack is deployed (CloudFront distribution and QuizAPI exist)

2. Install chaos SDK if missing:
```bash
python3 -c "import localstack.sdk.chaos" 2>/dev/null || \
  /opt/localstack-venv/bin/pip install localstack-sdk-python
```

3. Run automated chaos test:
```bash
pytest tests/test_outage.py -v
```

4. Point user to Chaos Engineering dashboard:
https://app.localstack.cloud/chaos-engineering

5. If test times out (nested-Docker sandbox issue), demonstrate chaos primitive directly:
```bash
python3 -c "from localstack.sdk.chaos import ChaosClient; \
  from localstack.sdk.models import FaultRule; \
  c=ChaosClient(); \
  c.set_fault_rules([FaultRule(region='us-east-1',service='dynamodb')]); \
  print(c.get_fault_rules()); c.set_fault_rules([])"
```

## Architecture
During DynamoDB outage:
1. CreateQuiz publishes to QuizzesWriteFailures SNS topic
2. Message lands in QuizzesWriteFailuresQueue (SQS)
3. RetryQuizzesWritesFunction processes queue and retries until DynamoDB is healthy

## License Note
Surface Enterprise license errors clearly - don't treat as application bugs.
