#!/usr/bin/env bash
# PreToolUse hook for Bash. Appends the command being run to the demo log so
# the tmux "agent commands" pane can stream it via `tail -f`.

set -u
LOG=${CLAUDE_DEMO_LOG:-/tmp/claude-commands.log}

mkdir -p "$(dirname "$LOG")"
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -n "$cmd" ]]; then
  # Indent continuation lines so multi-line commands are easy to read.
  printf '$ %s\n' "$cmd" | sed '2,$s/^/  /' >> "$LOG"
fi

exit 0
