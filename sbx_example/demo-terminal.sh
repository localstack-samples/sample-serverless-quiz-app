#!/usr/bin/env bash
# Launch a browser-embedded 2-pane tmux session for the LocalStack demo.
#
# Layout:
#   ┌─────────────────────────────────────────────────────┐
#   │  Agent commands (top)                               │
#   │  tail -f /tmp/claude-commands.log                   │
#   ├─────────────────────────────────────────────────────┤
#   │  LocalStack logs (bottom)                           │
#   │  docker logs -f localstack-main                     │
#   └─────────────────────────────────────────────────────┘
#
# Open in your host browser at: http://127.0.0.1:7681
#
# Usage:
#   sbx_example/demo-terminal.sh           # start (foreground; Ctrl-C to stop)
#   sbx_example/demo-terminal.sh --bg      # start in background
#   sbx_example/demo-terminal.sh --stop    # stop the session
#
set -euo pipefail

SESSION="${TMUX_SESSION:-lsdemo}"
PORT="${TTYD_PORT:-7681}"
LOG="${CLAUDE_DEMO_LOG:-/tmp/claude-commands.log}"

TTYD_OPTS=(
  --port "$PORT"
  --writable                       # allow keyboard input
  --check-origin                   # basic CSRF protection
  --terminal-type xterm-256color
  -t titleFixed='LocalStack Demo'
  -t 'theme={"background":"#0b0e14","foreground":"#bfbdb6"}'
  -t fontSize=13
)

stop() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  pkill -f "ttyd .* tmux .* $SESSION" 2>/dev/null || true
  echo "demo-terminal stopped"
}

[[ "${1:-}" == "--stop" ]] && { stop; exit 0; }

# Make sure the log file exists so `tail -f` doesn't error on startup.
mkdir -p "$(dirname "$LOG")"
[[ -f "$LOG" ]] || : > "$LOG"

# Tear down any previous session and start fresh.
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Build the 2-pane layout inside a detached tmux session.
# Pane 0 (top):    stream of agent commands & truncated output
# Pane 1 (bottom): live LocalStack container logs
tmux new-session  -d -s "$SESSION" -x 220 -y 50 -n demo
tmux split-window -v -t "$SESSION:demo.0" -p 50

# Top pane: stream the agent's commands as they're issued.
tmux send-keys -t "$SESSION:demo.0" \
  "clear && printf '\033[1;36m%s\033[0m\n' '— Agent commands (live) —' && \
   tail -n +1 -F '$LOG'" C-m

# Bottom pane: wait for the LocalStack container, then follow its logs.
# Wrapped in an outer `while true` so the pane resumes when the container is
# restarted (e.g. `localstack stop && make start` during a demo) instead of
# leaving a dead `docker logs` behind.
tmux send-keys -t "$SESSION:demo.1" \
  "clear && printf '\033[1;36m%s\033[0m\n' '— LocalStack logs (live) —' && \
   while true; do \
     while ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^localstack-main$'; do \
       echo 'waiting for localstack-main container...'; sleep 2; \
     done; \
     printf '\033[1;32m%s\033[0m\n' '— attached to localstack-main —'; \
     docker logs -f localstack-main 2>&1; \
     printf '\033[1;33m%s\033[0m\n' '— localstack-main exited; waiting for restart —'; \
     sleep 1; \
   done" C-m

# Focus the top pane.
tmux select-pane -t "$SESSION:demo.0"

URL="http://127.0.0.1:${PORT}"
echo
echo "tmux session '$SESSION' ready."
echo "Open this in your host browser:"
echo
echo "    $URL"
echo

if [[ "${1:-}" == "--bg" ]]; then
  nohup ttyd "${TTYD_OPTS[@]}" tmux attach-session -t "$SESSION" \
    > /tmp/ttyd.log 2>&1 &
  echo "ttyd backgrounded (PID $!); logs at /tmp/ttyd.log"
  echo "Stop with: $0 --stop"
else
  exec ttyd "${TTYD_OPTS[@]}" tmux attach-session -t "$SESSION"
fi
