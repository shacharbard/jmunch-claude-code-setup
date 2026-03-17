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

# Overwrite sentinel with ONLY "stale" — removes old "code"/"doc" lines
# so the sentinel-writer must re-add them after BOTH indexes run.
echo "stale" > "$SENTINEL"

cat <<'EOF'
HARD BLOCK: Commit detected — jCodeMunch/jDocMunch indexes are now STALE.
ALL tools are blocked until you re-index. Run BOTH immediately:
  1. mcp__jcodemunch__index_folder(path='.', incremental=true, use_ai_summaries=false)
  2. mcp__jdocmunch__index_local(path='.', use_ai_summaries=false)
EOF
