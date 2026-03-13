#!/bin/bash
# PostToolUse:Bash hook — soft nudge to re-index after git commits
# Uses a stdout message (not sentinel deletion) to avoid subagent deadlocks.
#
# Why soft nudge instead of hard block:
#   Subagents share the sentinel file but their PostToolUse hooks do NOT fire
#   the sentinel-writer. If a subagent commits and deletes the sentinel, no
#   subagent can recreate it — permanent deadlock. A soft nudge is safe for
#   both main sessions and subagents.
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

cat <<'EOF'
Commit detected — jCodeMunch/jDocMunch indexes may be stale.
Run BOTH of these now (they are fast, incremental):
  1. mcp__jcodemunch__index_folder(path='.', incremental=true, use_ai_summaries=false)
  2. mcp__jdocmunch__index_local(path='.', use_ai_summaries=false)
EOF
