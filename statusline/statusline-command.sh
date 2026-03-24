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

# Auto-clear stale "fetch failed" cache so limits retry immediately after re-login.
# VBW caches failures for 60s, but if the OAuth token rotated, retrying sooner helps.
if echo "$output" | LC_ALL=C grep -q "fetch failed"; then
  _UID=$(id -u)
  rm -f /tmp/vbw-*-"${_UID}"-*-slow 2>/dev/null
fi

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

# Use GENUINE savings from separate history files
# JCM history: ~/.code-index/_genuine_savings_history.jsonl
# JDM history: ~/.doc-index/_genuine_savings_history.jsonl
# CTX history: ~/.code-index/_genuine_savings_ctx_history.jsonl
jcm_history_file="$HOME/.code-index/_genuine_savings_history.jsonl"
jdm_history_file="$HOME/.doc-index/_genuine_savings_history.jsonl"
ctx_history_file="$HOME/.code-index/_genuine_savings_ctx_history.jsonl"
ctx_file="$HOME/.code-index/_genuine_savings_ctx.json"

jcm_raw=0; jdm_raw=0; ctx_raw=0
jcm_today=0; jdm_today=0; ctx_today=0
today=$(date -u +%Y-%m-%d)

# JCM totals and today
if [ -f "$jcm_history_file" ]; then
  jcm_raw=$(jq -s '[.[].tokens_saved] | add // 0' "$jcm_history_file" 2>/dev/null || echo "0")
  jcm_today=$(jq -s --arg d "$today" '[.[] | select(.ts[:10] == $d) | .tokens_saved] | add // 0' "$jcm_history_file" 2>/dev/null || echo "0")
fi

# JDM totals and today
if [ -f "$jdm_history_file" ]; then
  jdm_raw=$(jq -s '[.[].tokens_saved] | add // 0' "$jdm_history_file" 2>/dev/null || echo "0")
  jdm_today=$(jq -s --arg d "$today" '[.[] | select(.ts[:10] == $d) | .tokens_saved] | add // 0' "$jdm_history_file" 2>/dev/null || echo "0")
fi

# JCM authoritative total: use server-side _savings.json if higher than hook history
jcm_builtin="$HOME/.code-index/_savings.json"
if [ -f "$jcm_builtin" ]; then
  jcm_builtin_val=$(jq -r '.total_tokens_saved // 0' "$jcm_builtin" 2>/dev/null || echo "0")
  [ "$jcm_builtin_val" -gt "$jcm_raw" ] 2>/dev/null && jcm_raw=$jcm_builtin_val
fi

# JDM authoritative total: use server-side _savings.json if higher than hook history
jdm_builtin="$HOME/.doc-index/_savings.json"
if [ -f "$jdm_builtin" ]; then
  jdm_builtin_val=$(jq -r '.total_tokens_saved // 0' "$jdm_builtin" 2>/dev/null || echo "0")
  [ "$jdm_builtin_val" -gt "$jdm_raw" ] 2>/dev/null && jdm_raw=$jdm_builtin_val
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
  B=$'\033[1m'
  L=$'\033[38;5;183m'  # lilac (light purple)
  BG=$'\033[92m'       # bright green
  X=$'\033[0m'
  # JCM today
  jcm_today_part=""
  if [ "$jcm_today" -gt 0 ] 2>/dev/null; then
    jcm_td=$(format_tokens "$jcm_today")
    jcm_today_part=" ${D}(${X}${BG}today:${jcm_td}${X}${D})${X}"
  fi
  # JDM today
  jdm_today_part=""
  if [ "$jdm_today" -gt 0 ] 2>/dev/null; then
    jdm_td=$(format_tokens "$jdm_today")
    jdm_today_part=" ${D}(${X}${BG}today:${jdm_td}${X}${D})${X}"
  fi
  # CTX with today
  ctx_part=""
  if [ "$ctx_raw" -gt 0 ] 2>/dev/null; then
    ctx=$(format_tokens "$ctx_raw")
    ctx_today_part=""
    if [ "$ctx_today" -gt 0 ] 2>/dev/null; then
      ctx_td=$(format_tokens "$ctx_today")
      ctx_today_part=" ${D}(${X}${BG}today:${ctx_td}${X}${D})${X}"
    fi
    ctx_part=" ${B}${L}CTX:${X}${L}${ctx}${X}${ctx_today_part}"
  fi
  jmunch_suffix=" ${D}|${X} ${B}${L}JCM:${X}${L}${jcm}${X}${jcm_today_part} ${B}${L}JDM:${X}${L}${jdm}${X}${jdm_today_part}${ctx_part}"
fi

# Rearrange VBW output for cleaner layout:
#   VBW L1: [VBW] Phase │ Plans │ ...           → keep as-is
#   VBW L2: Context: ██ X% │ Tokens │ Cache     → append "│ VBW X.X │ CC X.X"
#   VBW L3: Session: ██ X% │ Weekly │ ...       → append "│ Model: ... │ Time: ..."
#   VBW L4: Model: ... │ Time │ VBW │ CC        → replace with JCM/JDM/CTX savings
#
# This avoids cramming everything onto L4.

total_lines=$(echo "$output" | wc -l | tr -d ' ')

if [ "$total_lines" -ge 4 ] && [ -n "$jmunch_suffix" ]; then
  D=$'\033[2m'
  X=$'\033[0m'

  L1=$(echo "$output" | sed -n '1p')
  L2=$(echo "$output" | sed -n '2p')
  L3=$(echo "$output" | sed -n '3p')
  L4=$(echo "$output" | sed -n '4p')

  # Extract "VBW X.X.X │ CC X.X.X" from L4 (dim text at end)
  # Pattern: "│ VBW ..." to end of line (after stripping ANSI for matching)
  vbw_cc=$(echo "$L4" | LC_ALL=C sed 's/\x1b\[[0-9;]*m//g' | grep -oE 'VBW [0-9]+\.[0-9]+\.[0-9]+ .* CC [^ ]+' | head -1)
  if [ -z "$vbw_cc" ]; then
    # Fallback: just grab everything after "Time: ..."
    vbw_cc=$(echo "$L4" | LC_ALL=C sed 's/\x1b\[[0-9;]*m//g' | grep -oE 'VBW [^ ]+' | head -1)
    cc_ver=$(echo "$L4" | LC_ALL=C sed 's/\x1b\[[0-9;]*m//g' | grep -oE 'CC [^ ]+' | head -1)
    [ -n "$cc_ver" ] && vbw_cc="$vbw_cc ${D}│${X} $cc_ver"
  fi

  # Extract "Model: ... │ Time: ..." from L4
  model_time=$(echo "$L4" | LC_ALL=C sed 's/\x1b\[[0-9;]*m//g' | grep -oE 'Model: .+ \(API: [^)]+\)' | head -1)

  # Append VBW/CC to L2 (context line)
  if [ -n "$vbw_cc" ]; then
    L2="${L2} ${D}│${X} ${D}${vbw_cc}${X}"
  fi

  # Append Model/Time to L3 (session/usage line)
  if [ -n "$model_time" ]; then
    if [ -n "$L3" ]; then
      L3="${L3} ${D}│${X} ${D}${model_time}${X}"
    else
      L3="${D}${model_time}${X}"
    fi
  fi

  # L4 becomes just the savings line
  printf '%b\n' "$L1"
  printf '%b\n' "$L2"
  [ -n "$L3" ] && printf '%b\n' "$L3"
  printf '%b\n' "${jmunch_suffix# }"
elif [ -n "$jmunch_suffix" ]; then
  # Fewer than 4 lines — just append to last line (fallback)
  echo "$output" | head -n $((total_lines - 1))
  last_line=$(echo "$output" | tail -1)
  printf '%b\n' "${last_line}${jmunch_suffix}"
else
  echo "$output"
fi

exit 0
