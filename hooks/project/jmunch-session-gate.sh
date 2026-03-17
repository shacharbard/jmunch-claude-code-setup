#!/bin/bash
# PreToolUse:* hook — BLOCK all tools until jCodeMunch + jDocMunch indexes are refreshed
# Exit 2 = block the tool call with message
# Exit 0 = allow
#
# Sentinel: /tmp/jmunch-ready-<hash of project root>
# Hash is derived from the git root (resolving worktrees and submodules),
# stable across process wrappers, subagents, worktrees, and non-root CWDs.
#
# Install: Copy to .claude/hooks/ in your project
# Register: PreToolUse matcher "*" in project .claude/settings.json
# Paired with: jmunch-session-start.sh, jmunch-sentinel-writer.sh

# Read stdin once — we need it for tool name extraction
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

# If sentinel has both "code" and "doc" lines AND no "stale" marker, session is ready
if [ -f "$SENTINEL" ]; then
  HAS_CODE=$(grep -c '^code$' "$SENTINEL" 2>/dev/null | head -1 || echo 0)
  HAS_DOC=$(grep -c '^doc$' "$SENTINEL" 2>/dev/null | head -1 || echo 0)
  IS_STALE=$(grep -c '^stale$' "$SENTINEL" 2>/dev/null | head -1 || echo 0)
  if [ "${HAS_CODE:-0}" -gt 0 ] 2>/dev/null && [ "${HAS_DOC:-0}" -gt 0 ] 2>/dev/null && [ "${IS_STALE:-0}" -eq 0 ] 2>/dev/null; then
    exit 0
  fi
fi

# Extract tool name from the already-read input
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Always allow: jCodeMunch/jDocMunch tools (needed to CREATE the sentinel)
case "$TOOL" in
  mcp__jcodemunch__*|mcp__jdocmunch__*) exit 0 ;;
esac

# Always allow: ToolSearch (needed to fetch deferred tool schemas for jmunch)
case "$TOOL" in
  ToolSearch) exit 0 ;;
esac

# Always allow: context-mode tools (they have their own session gate;
# blocking them here creates a deadlock when context-mode needs ctx_stats to init)
case "$TOOL" in
  mcp__context-mode__*) exit 0 ;;
esac

# Always allow: agent communication and lifecycle tools
# Blocking these traps subagents — they finish work but can't return results
case "$TOOL" in
  SendMessage|TaskUpdate|TaskCreate|TaskGet|TaskList|TaskOutput|TaskStop) exit 0 ;;
  Agent|ExitPlanMode|EnterPlanMode) exit 0 ;;
  AskUserQuestion) exit 0 ;;
esac

# Block everything else
echo "BLOCKED: jCodeMunch/jDocMunch indexes not yet refreshed this session.
You MUST run BOTH of these IMMEDIATELY before doing any other work:
  1. mcp__jcodemunch__index_folder(path='.', incremental=true, use_ai_summaries=false)
  2. mcp__jdocmunch__index_local(path='.', use_ai_summaries=false)
Do NOT respond to the user first. Run the indexes NOW. All tools are blocked until this is done." >&2
exit 2
