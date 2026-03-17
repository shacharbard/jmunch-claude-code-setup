#!/bin/bash
# PostToolUse hook for mcp__jcodemunch__index_folder and mcp__jdocmunch__index_local
# Writes sentinel lines to mark each index as refreshed for this session.
# Sentinel hash is derived from project directory (stable across wrappers/subagents).
#
# Install: Copy to .claude/hooks/ in your project
# Register: PostToolUse matchers for both index tools in project .claude/settings.json
# Paired with: jmunch-session-gate.sh, jmunch-session-start.sh

INPUT=$(cat)

# --- Stable Sentinel Path Computation ---
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$PROJECT_ROOT" ]; then
    _WALK="$PROJECT_ROOT"
    while true; do
        _PARENT="$(git -C "$_WALK" rev-parse --show-superproject-working-tree 2>/dev/null)"
        [ -z "$_PARENT" ] && break
        _WALK="$_PARENT"
    done
    PROJECT_ROOT="$_WALK"
fi
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(pwd -P)"
fi

# --- Git Worktree Detection ---
if [ -n "$PROJECT_ROOT" ]; then
    _GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"
    _GIT_COMMON="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null)"
    [ "${_GIT_DIR:0:1}" != "/" ]    && _GIT_DIR="$PROJECT_ROOT/$_GIT_DIR"
    [ "${_GIT_COMMON:0:1}" != "/" ] && _GIT_COMMON="$PROJECT_ROOT/$_GIT_COMMON"
    if [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
        _MAIN_ROOT="$(cd "$_GIT_COMMON/.." 2>/dev/null && pwd -P)"
        [ -n "$_MAIN_ROOT" ] && PROJECT_ROOT="$_MAIN_ROOT"
    fi
fi

HASH=$(echo "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "$PROJECT_ROOT" | md5sum | awk '{print $1}')
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
