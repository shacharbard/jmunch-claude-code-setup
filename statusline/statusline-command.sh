#!/bin/bash
# Wrapper: runs VBW statusline + appends jCodeMunch/jDocMunch token savings to L4
# This survives VBW plugin updates since it's outside the plugin cache.
#
# If you're NOT using VBW, see the standalone version at the bottom of this file.
#
# Install: Copy to ~/.claude/statusline-command.sh
# Register in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash \"$HOME/.claude/statusline-command.sh\"" }

input=$(cat)

# Find VBW statusline (version-agnostic — picks latest)
VBW_SL=""
for f in "$HOME"/.claude/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh; do
  [ -f "$f" ] && VBW_SL="$f"
done

if [ -z "$VBW_SL" ]; then
  echo "VBW statusline not found"
  exit 0
fi

# Run VBW statusline, capture output
output=$(echo "$input" | bash "$VBW_SL" 2>/dev/null)

# Compute jCodeMunch + jDocMunch savings
format_tokens() {
  local n="$1"
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    printf "%.3fM" "$(echo "scale=3; $n / 1000000" | bc)"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    printf "%.3fK" "$(echo "scale=3; $n / 1000" | bc)"
  else
    echo "$n"
  fi
}

# Use GENUINE savings (filtered by track-genuine-savings.sh hook)
# Aggregates across all per-agent files: _genuine_savings.json, _genuine_savings_{agent}.json
# Falls back to _savings.json if no genuine files exist yet
genuine_dir="$HOME/.code-index"
fallback_file="$HOME/.code-index/_savings.json"
jdm_file="$HOME/.doc-index/_savings.json"

jcm_raw=0; jdm_raw=0

# Compute all-time total from JSONL history (consistent with today's calculation)
# The _genuine_savings.json resets per session, but history accumulates across all sessions
history_file="$HOME/.code-index/_genuine_savings_history.jsonl"
if [ -f "$history_file" ]; then
  jcm_raw=$(jq -s '[.[].tokens_saved] | add // 0' "$history_file" 2>/dev/null || echo "0")
elif ls "$genuine_dir"/_genuine_savings*.json 1>/dev/null 2>&1; then
  jcm_raw=$(jq -s '[.[].total_genuine_tokens_saved // 0] | add // 0' "$genuine_dir"/_genuine_savings*.json 2>/dev/null || echo "0")
elif [ -f "$fallback_file" ]; then
  jcm_raw=$(jq -r '.total_tokens_saved // 0' "$fallback_file" 2>/dev/null || echo "0")
fi
[ -f "$jdm_file" ] && jdm_raw=$(jq -r '.total_tokens_saved // 0' "$jdm_file" 2>/dev/null || echo "0")

# Compute today's savings from JSONL history
today=$(date -u +%Y-%m-%d)
jcm_today=0
if [ -f "$history_file" ]; then
  jcm_today=$(jq -s --arg d "$today" '[.[] | select(.ts[:10] == $d) | .tokens_saved] | add // 0' "$history_file" 2>/dev/null || echo "0")
fi

# CTX savings from context-mode tracker (context-mode-jmunch-bridge)
ctx_file="$HOME/.code-index/_genuine_savings_ctx.json"
ctx_raw=0
[ -f "$ctx_file" ] && ctx_raw=$(jq -r '.total_genuine_tokens_saved // 0' "$ctx_file" 2>/dev/null || echo "0")

jmunch_suffix=""
if [ "$jcm_raw" -gt 0 ] 2>/dev/null || [ "$jdm_raw" -gt 0 ] 2>/dev/null || [ "$ctx_raw" -gt 0 ] 2>/dev/null; then
  jcm=$(format_tokens "$jcm_raw")
  jdm=$(format_tokens "$jdm_raw")
  D=$'\033[2m'
  C=$'\033[36m'
  Y=$'\033[33m'
  X=$'\033[0m'
  today_part=""
  if [ "$jcm_today" -gt 0 ] 2>/dev/null; then
    jcm_td=$(format_tokens "$jcm_today")
    today_part=" ${D}(${X}${Y}today:${jcm_td}${X}${D})${X}"
  fi
  ctx_part=""
  if [ "$ctx_raw" -gt 0 ] 2>/dev/null; then
    ctx=$(format_tokens "$ctx_raw")
    ctx_part=" CTX:${ctx}"
  fi
  jmunch_suffix=" ${D}|${X} ${C}JCM:${jcm}${today_part} JDM:${jdm}${ctx_part}${X}"
fi

# Append jmunch savings to the last line (L4: Model/time line)
if [ -n "$jmunch_suffix" ]; then
  total_lines=$(echo "$output" | wc -l | tr -d ' ')
  echo "$output" | head -n $((total_lines - 1))
  last_line=$(echo "$output" | tail -1)
  printf '%b\n' "${last_line}${jmunch_suffix}"
else
  echo "$output"
fi

exit 0
