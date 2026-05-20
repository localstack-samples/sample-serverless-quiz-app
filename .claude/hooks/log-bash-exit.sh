#!/usr/bin/env bash
# PostToolUse hook for Bash. Appends a truncated copy of stdout/stderr to the
# demo log so the tmux "agent commands" pane shows both the command and its
# (short) response. Followed by a blank line so consecutive commands render as
# visually separated blocks.

set -u
LOG=${CLAUDE_DEMO_LOG:-/tmp/claude-commands.log}
MAX_LINES=${CLAUDE_DEMO_MAX_LINES:-20}

input=$(cat)

# tool_response shape varies — it may be a raw string, or an object with
# .output / .stdout / .content. Try them in order.
output=$(printf '%s' "$input" | jq -r '
  .tool_response as $r
  | if   ($r | type) == "string" then $r
    elif ($r | type) == "object" then
      ( $r.output // $r.stdout // $r.stderr // $r.content // $r.text // "" )
    else "" end
' 2>/dev/null)

if [[ -n "$output" ]]; then
  total=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
  if (( total > MAX_LINES )); then
    printf '%s\n' "$output" | head -n "$MAX_LINES" | sed 's/^/  /' >> "$LOG"
    printf '  ... [%d more lines]\n' "$((total - MAX_LINES))" >> "$LOG"
  else
    printf '%s\n' "$output" | sed 's/^/  /' >> "$LOG"
  fi
fi

printf '\n' >> "$LOG"
exit 0
