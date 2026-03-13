#!/bin/bash
# PostToolUse:Bash hook — HARD BLOCK re-index after git commits
# Adds a "stale" marker to the sentinel, which the session gate checks.
# The sentinel-writer removes "stale" after both indexes are refreshed.
#
# This is subagent-safe because:
#   - The sentinel is NOT deleted (unlike the old rm -f approach)
#   - Subagents can recover: index tools are allowed through the gate,
#     and the sentinel-writer fires on PostToolUse for index tools
#     regardless of who (main agent or subagent) runs them.
#
# Install: Copy to .claude/hooks/ in your project
# Register: PostToolUse matcher "Bash" in project .claude/settings.json

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only trigger on git commit commands
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Check if commit actually succeeded
OUTPUT=$(echo "$INPUT" | jq -r '.tool_output.stdout // ""')
case "$OUTPUT" in
  *"nothing to commit"*|*"no changes"*) exit 0 ;;
esac

# Mark the sentinel as stale — the session gate will block until re-indexed
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
if [ -z "$CWD" ]; then
  CWD=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
HASH=$(echo "$CWD" | md5 -q 2>/dev/null || echo "$CWD" | md5sum 2>/dev/null | cut -c1-32)
SENTINEL="/tmp/jmunch-ready-${HASH}"

grep -q '^stale$' "$SENTINEL" 2>/dev/null || echo "stale" >> "$SENTINEL"

cat <<'EOF'
HARD BLOCK: Commit detected — jCodeMunch/jDocMunch indexes are now STALE.
ALL tools are blocked until you re-index. Run BOTH immediately:
  1. mcp__jcodemunch__index_folder(path='.', incremental=true, use_ai_summaries=false)
  2. mcp__jdocmunch__index_local(path='.', use_ai_summaries=false)
EOF
