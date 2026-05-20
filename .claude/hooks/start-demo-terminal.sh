#!/usr/bin/env bash
# SessionStart hook. Launches the 2-pane demo terminal in the background so
# the human watching the browser at http://127.0.0.1:7681 sees commands and
# LocalStack logs streaming as soon as the agent starts working.
#
# Idempotent and self-healing:
#   - Sources the sandbox persistent env so PATH additions (nvm/sdkman/etc.)
#     are available to the hook.
#   - Installs ttyd + tmux if missing (silent apt-get).
#   - If ttyd is already listening on $TTYD_PORT, leaves it alone.

set -u

# Source persistent environment so any tools installed there (nvm, sdkman,
# user-pip bins, etc.) are on PATH. This file is also sourced before each
# Bash tool invocation, but hooks bypass that path.
if [[ -r /etc/sandbox-persistent.sh ]]; then
  # shellcheck disable=SC1091
  . /etc/sandbox-persistent.sh
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG=${CLAUDE_DEMO_LOG:-/tmp/claude-commands.log}
PORT=${TTYD_PORT:-7681}

# Fresh log file every session so the viewer doesn't see stale history.
: > "$LOG"

# Install ttyd + tmux on demand if either is missing. Stay quiet on success;
# any failure here is non-fatal — the hook must never block session startup.
if ! command -v ttyd >/dev/null || ! command -v tmux >/dev/null; then
  if command -v apt-get >/dev/null; then
    sudo -n apt-get update -qq >/dev/null 2>&1 || true
    sudo -n apt-get install -y -qq tmux ttyd >/dev/null 2>&1 || true
  fi
fi

# If ttyd is already serving the demo on $PORT, do nothing — avoids killing
# an active viewer session when a new agent session starts. curl is used
# instead of ss because the latter doesn't see sockets in some sandbox
# network namespaces.
if curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/" 2>/dev/null; then
  exit 0
fi

# Bail quietly if install didn't take — better to skip the demo viewer than
# block the session on a tooling problem.
command -v ttyd >/dev/null && command -v tmux >/dev/null || exit 0

# demo-terminal.sh is idempotent: tears down any prior tmux session before
# starting a fresh one.
"$REPO_ROOT/sbx_example/demo-terminal.sh" --bg >/dev/null 2>&1 || true

exit 0
