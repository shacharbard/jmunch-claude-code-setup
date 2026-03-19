#!/bin/bash
# PreToolUse:Bash hook — redirect large-output commands to context-mode ctx_execute
# Exit 2 = block with instruction to use ctx_execute
# Exit 0 = allow (small/simple commands)
#
# This hook completes the three-tier token savings:
#   jcodemunch-nudge.sh      -> blocks Read on .py/.ts/.tsx (use get_symbol)
#   jdocmunch-nudge.sh       -> blocks Read on large .md (use get_section)
#   context-mode-nudge.sh    -> blocks Read on large .json/.html (use ctx_execute_file)
#   context-mode-bash-nudge.sh -> blocks Bash on large-output commands (use ctx_execute)

INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# No command = allow
[ -z "$CMD" ] && exit 0

# Skip if context-mode is not configured in this project
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
if [ -n "$CWD" ]; then
  MCP_FILE="$CWD/.mcp.json"
else
  MCP_FILE=".mcp.json"
fi
if [ ! -f "$MCP_FILE" ] || ! grep -q 'context-mode' "$MCP_FILE" 2>/dev/null; then
  exit 0
fi

# ─── ALWAYS ALLOW (small/safe commands) ───────────────────────────
# git status, git add, git commit, git push, git checkout, git branch
case "$CMD" in
  "git status"*|"git add "*|"git commit "*|"git push"*|"git pull"*) exit 0 ;;
  "git checkout "*|"git branch"*|"git stash"*|"git merge "*) exit 0 ;;
  "git tag "*|"git remote "*|"git fetch"*|"git rebase "*) exit 0 ;;
  "git config "*|"git init"*|"git clone "*) exit 0 ;;
esac

# Short git diff/log with limits are fine
case "$CMD" in
  *"git diff --stat"*|*"git diff --name"*) exit 0 ;;
  *"git log -"[0-9]*|*"git log --oneline"*) exit 0 ;;
  *"git log -n "[0-9]*) exit 0 ;;
esac

# Simple filesystem commands
case "$CMD" in
  "ls"*|"pwd"|"which "*|"echo "*|"date"*|"id"*|"whoami"*) exit 0 ;;
  "mkdir "*|"rmdir "*|"touch "*|"chmod "*|"mv "*|"cp "*) exit 0 ;;
  "cd "*|"wc "*|"head -"*|"tail -"*|"basename "*|"dirname "*) exit 0 ;;
esac

# Package management (install/add are fine — output is progress, not data)
case "$CMD" in
  "npm install"*|"npm ci"*|"pip install"*|"uv "*) exit 0 ;;
  "npx "*|"pnpm "*|"yarn "*) exit 0 ;;
esac

# Single file operations with small expected output
case "$CMD" in
  "cat "*|"head "*|"tail "*) exit 0 ;;  # Already handled by Read hook
esac

# jq on small inputs / piped chains that filter
case "$CMD" in
  "jq "*) exit 0 ;;
esac

# Allow commands that write files (build, compile) — output is side effect, not data
case "$CMD" in
  "npm run build"*|"npm run lint"*|"npm run typecheck"*) exit 0 ;;
  "python"*"-c "*|"python3"*"-c "*) exit 0 ;;  # Inline python one-liners are usually small
  "python"*"-m pip"*|"python3"*"-m pip"*) exit 0 ;;  # Package management
  "python"*"-m json.tool"*|"python3"*"-m json.tool"*) exit 0 ;;  # Small utility
esac

# Allow any command with output redirected to a file (> or >>)
case "$CMD" in
  *" > "*|*" >> "*) exit 0 ;;
esac

# Allow HASH/sentinel creation commands (our own infrastructure)
case "$CMD" in
  *"jmunch-ready"*|*"jmunch-session"*|*"md5"*) exit 0 ;;
esac

# ─── BLOCK: Commands likely to produce large output ───────────────

# Test suites (pytest, npm test, jest, mocha, vitest)
IS_TEST=""
case "$CMD" in
  *"pytest"*|*"npm test"*|*"npm run test"*) IS_TEST=1 ;;
  *"jest "*|*"vitest"*|*"mocha"*|*"cargo test"*) IS_TEST=1 ;;
  *"python -m pytest"*|*"python -m unittest"*) IS_TEST=1 ;;
esac

# git log/diff without limits
IS_GIT_LARGE=""
case "$CMD" in
  *"git log"*) IS_GIT_LARGE=1 ;;   # Unlimited git log
  *"git diff"*) IS_GIT_LARGE=1 ;;  # Full diff can be huge
esac

# find/grep without limits (already handled by Grep tool, but catch shell usage)
IS_SEARCH=""
case "$CMD" in
  "find "*|"grep -r"*|"grep -R"*|"rg "*) IS_SEARCH=1 ;;
  *"| grep"*) ;; # Piped grep is filtering, not searching — allow
esac

# curl/wget (API responses can be huge)
IS_FETCH=""
case "$CMD" in
  *"curl "*|*"wget "*|*"http "*) IS_FETCH=1 ;;
esac

# Build/compile with verbose output
IS_BUILD=""
case "$CMD" in
  *"make "*|*"cargo build"*|*"tsc "*) IS_BUILD=1 ;;
esac

# Python scripts (running .py files — output can be large)
# Safe patterns (inline -c, -m pip, -m json.tool, output redirected) already exit 0 above
IS_PYTHON_SCRIPT=""
case "$CMD" in
  "python "*.py*|"python3 "*.py*) IS_PYTHON_SCRIPT=1 ;;
  "python scripts/"*|"python3 scripts/"*) IS_PYTHON_SCRIPT=1 ;;
esac

# If none of the large-output patterns matched, allow
if [ -z "$IS_TEST" ] && [ -z "$IS_GIT_LARGE" ] && [ -z "$IS_SEARCH" ] && [ -z "$IS_FETCH" ] && [ -z "$IS_BUILD" ] && [ -z "$IS_PYTHON_SCRIPT" ]; then
  exit 0
fi

# Capture project root for cd prefix (ctx_execute runs in a temp sandbox)
PROJECT_ROOT="$(pwd)"

# Build the redirect message
if [ -n "$IS_TEST" ]; then
  REASON="Test suite output can be very large"
elif [ -n "$IS_GIT_LARGE" ]; then
  REASON="Unbounded git log/diff can produce thousands of lines"
elif [ -n "$IS_SEARCH" ]; then
  REASON="Recursive search can return thousands of matches"
elif [ -n "$IS_FETCH" ]; then
  REASON="API/web responses can be very large"
elif [ -n "$IS_BUILD" ]; then
  REASON="Build output can be verbose"
elif [ -n "$IS_PYTHON_SCRIPT" ]; then
  REASON="Python script output can be large"
fi

cat <<EOF >&2
BLOCKED: $REASON. Use context-mode ctx_execute instead of Bash to keep large output out of conversation context.

IMPORTANT: ctx_execute runs in a temp sandbox, so you MUST cd to the project root first.

Instead of Bash, run:
  mcp__context-mode__ctx_execute(language="shell", code="cd $PROJECT_ROOT && $CMD")

For Python scripts, prefix with os.chdir:
  mcp__context-mode__ctx_execute(language="python", code="import os; os.chdir('$PROJECT_ROOT')\n...")

This executes the command in a sandbox — only filtered stdout enters your context window (98% token savings on large outputs).

If output exceeds 5KB, context-mode automatically applies intent-driven filtering to return only relevant portions.

Bash is allowed for: git operations (status/add/commit/push), file management (ls/mkdir/mv), package installs, small commands, and any command with output redirected to a file.
EOF
exit 2
