#!/bin/bash
# PreToolUse:* hook — BLOCK all tools until jCodeMunch + jDocMunch indexes are refreshed
# Exit 2 = block the tool call with message
# Exit 0 = allow
#
# Sentinel: /tmp/jmunch-session-ready-<PPID>
# PPID = Claude Code process ID, stable per session, dies on restart.
#
# Install: Copy to .claude/hooks/ in your project
# Register: PreToolUse matcher "*" in project .claude/settings.json
# Paired with: jmunch-session-start.sh, jmunch-sentinel-writer.sh

SENTINEL="/tmp/jmunch-session-ready-${PPID}"

# If sentinel has both "code" and "doc" lines, session is ready — allow everything
if [ -f "$SENTINEL" ]; then
  HAS_CODE=$(grep -c '^code$' "$SENTINEL" 2>/dev/null | head -1 || echo 0)
  HAS_DOC=$(grep -c '^doc$' "$SENTINEL" 2>/dev/null | head -1 || echo 0)
  if [ "${HAS_CODE:-0}" -gt 0 ] 2>/dev/null && [ "${HAS_DOC:-0}" -gt 0 ] 2>/dev/null; then
    exit 0
  fi
fi

# Read tool name from hook input
INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Always allow: jCodeMunch/jDocMunch tools (needed to CREATE the sentinel)
case "$TOOL" in
  mcp__jcodemunch__*|mcp__jdocmunch__*) exit 0 ;;
esac

# Always allow: ToolSearch (needed to fetch deferred tool schemas for jmunch)
case "$TOOL" in
  ToolSearch) exit 0 ;;
esac

# Block everything else
echo "BLOCKED: jCodeMunch/jDocMunch indexes not yet refreshed this session.
You MUST run BOTH of these IMMEDIATELY before doing any other work:
  1. mcp__jcodemunch__index_folder(path='.', incremental=true, use_ai_summaries=false)
  2. mcp__jdocmunch__index_local(path='.', use_ai_summaries=false)
Do NOT respond to the user first. Run the indexes NOW. All tools are blocked until this is done."
exit 2
