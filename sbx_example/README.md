# LocalStack Serverless Quiz Demo — Runbook

A self-driving demo of LocalStack running a serverless quiz app inside an `sbx`
sandbox. A Claude agent does the work; a browser-embedded tmux session lets you
watch every command and every LocalStack log line live.

```
┌─────────────────────────────────────────────────────┐
│  Agent commands (live)                              │
├─────────────────────────────────────────────────────┤
│  LocalStack logs (live)                             │
└─────────────────────────────────────────────────────┘
                http://127.0.0.1:7681
```

## Prerequisites

- `sbx` installed on your host & Anthropic token set
  - `op read "op://Dev/anthropic/token"  | sbx secret set -g anthropic`
- A LocalStack auth token: https://app.localstack.cloud/workspace/auth-token
- Two terminal windows, one to show sbx commands and the other to interact with Claude

Inside the sandbox the agent uses the `localstack` CLI (installed via pip into
a virtualenv) plus AWS CLI v2 and `awslocal` (from `awscli-local`). The
preflight script installs everything from scratch.

## 1. Create the sandbox

```bash
git clone https://github.com/localstack-samples/sample-serverless-quiz-app.git
cd sample-serverless-quiz-app
sbx run claude --name localstack-test
```

Walk through the interactive prompt to setup a new sandbox, call it `localstack-test`, and select Claude  

## 2. Inject your LocalStack auth token

```bash
# short term hack until base64 credential swapping available in sbx
sbx exec -d localstack-test bash -c \
  "echo 'export LOCALSTACK_AUTH_TOKEN=ls-YOUR-TOKEN-HERE' >> /etc/sandbox-persistent.sh"
```
The token will be loaded by the agent for it's shell commands in the future. This goes away and the user should store their token as a credential once we support it.

## 3. Publish ports

```bash
sbx ports localstack-test --publish 7681:7681/tcp   # demo terminal (browser)
sbx ports localstack-test --publish 4566:4566/tcp   # LocalStack API
sbx ports localstack-test --publish 8443:443/tcp # Currently some URLs don't work because we can't map privileged hosts ports (443) to the Container, how can we set localstack pro to use 8443 consistently?
```

Port `4566` must be reachable so the LocalStack web console
(`app.localstack.cloud/inst/default/…`) can connect back to your instance and so
the extension URLs (`*.localhost.localstack.cloud:4566`) resolve.

## 4. Start the agent

Start the demo with the claude prompt:
  "Read sbx_example/AGENT_deploy.md and execute the deploy task"

A `SessionStart` hook (see `.claude/settings.json`) launches the 2-pane demo
terminal as soon as the agent starts. Open it in your browser:

> **http://127.0.0.1:7681**

- **Top pane** — every command the agent runs, followed by truncated output.
  Fed by `PreToolUse`/`PostToolUse` hooks that append to `/tmp/claude-commands.log`.
- **Bottom pane** — `docker logs -f localstack-main`. Waits for the container,
  then streams every AWS API call LocalStack handles.

## 5. Run more demos

Once the deploy finishes, prompt the agent with any of the other runbooks in
`AGENT_*.md` the same way:

```bash
"Read sbx_example/AGENT_iam.md and execute it"
```

| Runbook | Time | What it shows |
|---------|------|---------------|
| `AGENT_iam.md` | ~3 min | IAM Policy Stream: catch & patch a missing SQS permission |
| `AGENT_chaos.md` | ~3 min | Chaos Engineering: DynamoDB outage + recovery |
| `AGENT_mail.md` | ~2 min | SES → MailHog: inspect a real email |

## Monitoring URLs

Open these in additional browser tabs while the demo runs:

- Resource Browser — https://app.localstack.cloud/inst/default/resources
- Policy Stream — https://app.localstack.cloud/inst/default/policy-stream
- Chaos Engineering — https://app.localstack.cloud/inst/default/chaos-engineering
- MailHog (local) — http://mailhog.localhost.localstack.cloud:4566/

## Tmux navigation (inside the browser terminal)

The terminal at `http://127.0.0.1:7681` is a tmux session. Default prefix is
`Ctrl-b`:

| Key | Action |
|-----|--------|
| `Ctrl-b` `↑` / `↓` | Move between panes |
| `Ctrl-b` `z` | Zoom current pane to full screen (toggle) |
| `Ctrl-b` `[` | Enter scrollback mode — arrows / PgUp / PgDn to scroll, `q` to exit |
| `Ctrl-b` `d` | Detach (leaves session running) |
| `tmux attach -t lsdemo` | Re-attach from any sandbox shell |

## Tearing down

```bash
# Inside the sandbox: stop LocalStack (optional, saves a bit on shutdown)
sbx exec localstack-test localstack stop

# On the host: throw out the whole microvm and start over :-D
sbx rm localstack-test
```

## How it's wired

- `.claude/settings.json` — registers the three hooks
- `.claude/hooks/start-demo-terminal.sh` — `SessionStart` → runs `demo-terminal.sh --bg`
- `.claude/hooks/log-bash-command.sh` — `PreToolUse` on Bash → appends `$ <cmd>`
- `.claude/hooks/log-bash-exit.sh` — `PostToolUse` on Bash → appends up to 20 lines of output
- `sbx_example/demo-terminal.sh` — builds the tmux+ttyd session

Override the log path or output cap via env vars: `CLAUDE_DEMO_LOG`,
`CLAUDE_DEMO_MAX_LINES`. Override the tmux/ttyd target via `TMUX_SESSION`,
`TTYD_PORT`.

## Troubleshooting

- **`http://127.0.0.1:7681` won't load** — `localhost` doesn't resolve for
  sandbox-published ports on every host. Use the literal `127.0.0.1`. Verify
  the port is published: `sbx ports localstack-test`.
- **Top pane stays empty** — the hooks only fire on a fresh Claude session.
  After cloning, the first `sbx exec localstack-test claude …` invocation
  wires them up. If you started Claude before `.claude/settings.json` existed,
  exit and re-run.
- **Bottom pane stuck on "waiting for localstack-main"** — the container
  hasn't started yet. It comes up during deploy (via `make start`, which
  runs `localstack start -d`).

## Reference

Files in this directory:

- `AGENT_*.md` — per-demo runbooks the agent reads
- `docker-agent.yaml` — agent profile (alt entry point via `docker-agent run`)
- `demo-terminal.sh` — 2-pane tmux+ttyd launcher
- `pre-demo-check.sh` — preflight script (tool/credential check)
