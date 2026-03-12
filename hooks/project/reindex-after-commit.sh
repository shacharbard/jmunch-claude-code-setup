#!/bin/bash
# PostToolUse:Bash hook — clear sentinel + force re-index after git commits
# Clearing the sentinel blocks all tools until indexes are refreshed again.
# Uses PPID (Claude Code PID) as session identifier.
#
# Install: Copy to .claude/hooks/ in your project
# Register: PostToolUse matcher "Bash" in project .claude/settings.json
# Paired with: jmunch-session-gate.sh (enforces the block)

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

# Clear the sentinel — this blocks all tools until re-index
SENTINEL="/tmp/jmunch-session-ready-${PPID}"
rm -f "$SENTINEL"

cat <<'EOF'
Commit detected — jCodeMunch/jDocMunch indexes are now stale.
Run BOTH of these immediately (they are fast, incremental):
  1. mcp__jcodemunch__index_folder(path='.', incremental=true, use_ai_summaries=false)
  2. mcp__jdocmunch__index_local(path='.', use_ai_summaries=false)
All other tools are BLOCKED until both indexes are refreshed.
EOF
