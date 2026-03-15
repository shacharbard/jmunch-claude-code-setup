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

# Use GENUINE savings from JSONL history files
# history tracks all jCodeMunch + jDocMunch events (split by tool prefix)
# ctx_history tracks all context-mode events
history_file="$HOME/.code-index/_genuine_savings_history.jsonl"
ctx_history_file="$HOME/.code-index/_genuine_savings_ctx_history.jsonl"
ctx_file="$HOME/.code-index/_genuine_savings_ctx.json"
genuine_dir="$HOME/.code-index"

jcm_raw=0; jdm_raw=0; ctx_raw=0
jcm_today=0; jdm_today=0; ctx_today=0
today=$(date -u +%Y-%m-%d)

# JCM + JDM totals and today from history (split by tool prefix)
if [ -f "$history_file" ]; then
  jcm_raw=$(jq -s '[.[] | select(.tool | startswith("mcp__jcodemunch__")) | .tokens_saved] | add // 0' "$history_file" 2>/dev/null || echo "0")
  jdm_raw=$(jq -s '[.[] | select(.tool | startswith("mcp__jdocmunch__")) | .tokens_saved] | add // 0' "$history_file" 2>/dev/null || echo "0")
  jcm_today=$(jq -s --arg d "$today" '[.[] | select(.ts[:10] == $d) | select(.tool | startswith("mcp__jcodemunch__")) | .tokens_saved] | add // 0' "$history_file" 2>/dev/null || echo "0")
  jdm_today=$(jq -s --arg d "$today" '[.[] | select(.ts[:10] == $d) | select(.tool | startswith("mcp__jdocmunch__")) | .tokens_saved] | add // 0' "$history_file" 2>/dev/null || echo "0")
fi

# JDM fallback: jDocMunch reports tokens_saved=0 for most ops (search returns summaries),
# so history may have no JDM entries. Fall back to jDocMunch's built-in tracker.
if [ "$jdm_raw" -eq 0 ] 2>/dev/null; then
  jdm_builtin="$HOME/.doc-index/_savings.json"
  [ -f "$jdm_builtin" ] && jdm_raw=$(jq -r '.total_tokens_saved // 0' "$jdm_builtin" 2>/dev/null || echo "0")
fi

# CTX total: use the higher of history sum vs JSON accumulator
# (history may start later than JSON, so JSON can have older savings not in history)
ctx_hist_total=0; ctx_json_total=0
if [ -f "$ctx_history_file" ]; then
  ctx_hist_total=$(jq -s '[.[].tokens_saved] | add // 0' "$ctx_history_file" 2>/dev/null || echo "0")
  ctx_today=$(jq -s --arg d "$today" '[.[] | select(.ts[:10] == $d) | .tokens_saved] | add // 0' "$ctx_history_file" 2>/dev/null || echo "0")
fi
if [ -f "$ctx_file" ]; then
  ctx_json_total=$(jq -r '.total_genuine_tokens_saved // 0' "$ctx_file" 2>/dev/null || echo "0")
fi
# Use whichever is higher (JSON has pre-history savings, history has daily breakdown)
if [ "$ctx_json_total" -gt "$ctx_hist_total" ] 2>/dev/null; then
  ctx_raw=$ctx_json_total
else
  ctx_raw=$ctx_hist_total
fi

jmunch_suffix=""
if [ "$jcm_raw" -gt 0 ] 2>/dev/null || [ "$jdm_raw" -gt 0 ] 2>/dev/null || [ "$ctx_raw" -gt 0 ] 2>/dev/null; then
  jcm=$(format_tokens "$jcm_raw")
  jdm=$(format_tokens "$jdm_raw")
  D=$'\033[2m'
  C=$'\033[36m'
  Y=$'\033[33m'
  X=$'\033[0m'
  # JCM today
  jcm_today_part=""
  if [ "$jcm_today" -gt 0 ] 2>/dev/null; then
    jcm_td=$(format_tokens "$jcm_today")
    jcm_today_part=" ${D}(${X}${Y}today:${jcm_td}${X}${D})${X}"
  fi
  # JDM today
  jdm_today_part=""
  if [ "$jdm_today" -gt 0 ] 2>/dev/null; then
    jdm_td=$(format_tokens "$jdm_today")
    jdm_today_part=" ${D}(${X}${Y}today:${jdm_td}${X}${D})${X}"
  fi
  # CTX with today
  ctx_part=""
  if [ "$ctx_raw" -gt 0 ] 2>/dev/null; then
    ctx=$(format_tokens "$ctx_raw")
    ctx_today_part=""
    if [ "$ctx_today" -gt 0 ] 2>/dev/null; then
      ctx_td=$(format_tokens "$ctx_today")
      ctx_today_part=" ${D}(${X}${Y}today:${ctx_td}${X}${D})${X}"
    fi
    ctx_part=" CTX:${ctx}${ctx_today_part}"
  fi
  jmunch_suffix=" ${D}|${X} ${C}JCM:${jcm}${jcm_today_part} JDM:${jdm}${jdm_today_part}${ctx_part}${X}"
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
