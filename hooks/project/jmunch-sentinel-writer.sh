#!/bin/bash
# PostToolUse hook for mcp__jcodemunch__index_folder and mcp__jdocmunch__index_local
# Writes sentinel lines to mark each index as refreshed for this session.
# Sentinel hash is derived from project directory (stable across wrappers/subagents).
#
# Install: Copy to .claude/hooks/ in your project
# Register: PostToolUse matchers for both index tools in project .claude/settings.json
# Paired with: jmunch-session-gate.sh, jmunch-session-start.sh

INPUT=$(cat)
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
if [ -z "$CWD" ]; then
  CWD=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
HASH=$(echo "$CWD" | md5 -q 2>/dev/null || echo "$CWD" | md5sum 2>/dev/null | cut -c1-32)
SENTINEL="/tmp/jmunch-ready-${HASH}"

TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

case "$TOOL" in
  mcp__jcodemunch__index_folder)
    grep -q '^code$' "$SENTINEL" 2>/dev/null || echo "code" >> "$SENTINEL"
    ;;
  mcp__jdocmunch__index_local)
    grep -q '^doc$' "$SENTINEL" 2>/dev/null || echo "doc" >> "$SENTINEL"
    ;;
esac

# Check if both are now ready
if [ -f "$SENTINEL" ]; then
  HAS_CODE=$(grep -c '^code$' "$SENTINEL" 2>/dev/null | head -1 || echo 0)
  HAS_DOC=$(grep -c '^doc$' "$SENTINEL" 2>/dev/null | head -1 || echo 0)
  if [ "${HAS_CODE:-0}" -gt 0 ] 2>/dev/null && [ "${HAS_DOC:-0}" -gt 0 ] 2>/dev/null; then
    # Remove stale marker now that both indexes are fresh
    if grep -q '^stale$' "$SENTINEL" 2>/dev/null; then
      grep -v '^stale$' "$SENTINEL" > "${SENTINEL}.tmp" && mv "${SENTINEL}.tmp" "$SENTINEL"
    fi
    echo "jCodeMunch + jDocMunch indexes refreshed — all tools unblocked."
    exit 0
  fi
fi

# Tell the user which one is still pending
if [ -f "$SENTINEL" ]; then
  HAS_CODE=$(grep -c '^code$' "$SENTINEL" 2>/dev/null | head -1 || echo 0)
  HAS_DOC=$(grep -c '^doc$' "$SENTINEL" 2>/dev/null | head -1 || echo 0)
  if [ "${HAS_CODE:-0}" -gt 0 ] 2>/dev/null; then
    echo "jCodeMunch indexed. Still waiting for jDocMunch (mcp__jdocmunch__index_local)."
  elif [ "${HAS_DOC:-0}" -gt 0 ] 2>/dev/null; then
    echo "jDocMunch indexed. Still waiting for jCodeMunch (mcp__jcodemunch__index_folder)."
  fi
else
  echo "First index done. Still waiting for the other one before tools are unblocked."
fi
