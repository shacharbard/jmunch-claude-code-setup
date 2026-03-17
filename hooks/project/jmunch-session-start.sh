#!/bin/bash
# SessionStart hook — instruct the LLM to reindex jCodeMunch + jDocMunch
# before doing anything else. Output becomes a system prompt injection.
#
# Install: Copy to .claude/hooks/ in your project
# Register: SessionStart in project .claude/settings.json
#
# Paired with: jmunch-session-gate.sh (blocks tools until indexes are ready)
#              jmunch-sentinel-writer.sh (marks indexes as ready)

# Derive sentinel from project directory (stable across worktrees/submodules/subdirs)
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

# Clean up stale sentinel from any previous session
rm -f "$SENTINEL"

cat <<'PROMPT'
**MANDATORY FIRST ACTION — do this BEFORE responding to the user:**

1. Fetch the tool schemas: `ToolSearch("select:mcp__jcodemunch__index_folder,mcp__jdocmunch__index_local")`
2. Run BOTH in parallel:
   - `mcp__jcodemunch__index_folder(path=".", incremental=true, use_ai_summaries=false)`
   - `mcp__jdocmunch__index_local(path=".", use_ai_summaries=false)`
3. After both complete, tell the user: "jCodeMunch + jDocMunch indexes refreshed." Then proceed with whatever the user asked.

Do NOT skip this. Do NOT respond to the user first. Index refresh is the very first thing you do.
PROMPT
