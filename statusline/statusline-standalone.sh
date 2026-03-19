#!/bin/bash
# Standalone statusline with JCM/JDM savings counters (no VBW dependency)
#
# Install: Copy to ~/.claude/statusline-command.sh
# Register in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash \"$HOME/.claude/statusline-command.sh\"" }

RESET=$'\e[0m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RED=$'\e[31m'
GRAY=$'\e[90m'
CYAN=$'\e[36m'

input=$(cat)

folder=$(echo "$input" | jq -r '.workspace.current_dir // ""' | xargs basename 2>/dev/null)
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')

if [ "$pct" -lt 50 ] 2>/dev/null; then color="$GREEN"
elif [ "$pct" -lt 80 ] 2>/dev/null; then color="$YELLOW"
else color="$RED"; fi

filled=$((pct / 10))
empty=$((10 - filled))
bar=""
for ((i = 0; i < filled; i++)); do bar+="$'\xe2\x96\x88'"; done
for ((i = 0; i < empty; i++)); do bar+="$'\xe2\x96\x91'"; done

now=$(date +%H:%M)

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

# Read genuine savings from separate files
jcm_file="$HOME/.code-index/_genuine_savings.json"
jdm_file="$HOME/.doc-index/_genuine_savings.json"
jcm_raw=0; jdm_raw=0
if [ -f "$jcm_file" ]; then
    jcm_raw=$(jq -r '.total_genuine_tokens_saved // 0' "$jcm_file" 2>/dev/null || echo 0)
fi
if [ -f "$jdm_file" ]; then
    jdm_raw=$(jq -r '.total_genuine_tokens_saved // 0' "$jdm_file" 2>/dev/null || echo 0)
fi
jcm=$(format_tokens "$jcm_raw")
jdm=$(format_tokens "$jdm_raw")

echo "${GRAY}${folder}${RESET}  ${color}${bar}${RESET} ${color}${pct}%${RESET}  ${CYAN}JCM:${jcm} JDM:${jdm}${RESET}  ${GRAY}${now}${RESET}"
