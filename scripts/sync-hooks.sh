#!/bin/bash
# sync-hooks.sh — Symlink all jmunch hooks to ~/.claude/hooks/
#
# Run from anywhere. Pulls latest from the repo, then creates symlinks
# so all projects use the same hooks. No more copying or chmod.
#
# Usage:
#   bash ~/Development/AI/jmunch-claude-code-setup/scripts/sync-hooks.sh
#
# What it does:
#   1. git pull (if in a git repo with a remote)
#   2. Symlink hooks/global/*.sh and hooks/project/*.sh → ~/.claude/hooks/
#   3. Symlink statusline/*.sh → ~/.claude/
#
# After first run, updating is just: git pull in the repo.
# The symlinks point to the repo files, so changes are instant.

set -euo pipefail

# Find the repo root (this script lives in scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HOOKS_DIR="$HOME/.claude/hooks"
CLAUDE_DIR="$HOME/.claude"

echo "================================="
echo "  jmunch hook sync"
echo "================================="
echo ""
echo "  Repo: $REPO_ROOT"
echo ""

# --- Step 1: Pull latest ---
if [ -d "$REPO_ROOT/.git" ]; then
  REMOTE=$(git -C "$REPO_ROOT" remote 2>/dev/null | head -1)
  if [ -n "$REMOTE" ]; then
    echo "→ Pulling latest..."
    if git -C "$REPO_ROOT" pull --ff-only 2>&1; then
      echo "  ✓ Up to date"
    else
      echo "  ⚠ Pull failed (continuing with local files)"
    fi
  else
    echo "→ No remote configured, skipping pull"
  fi
fi
echo ""

# --- Step 2: Create hooks directory ---
mkdir -p "$HOOKS_DIR"

# --- Step 3: Symlink hooks ---
LINKED=0
SKIPPED=0

link_file() {
  local src="$1"
  local dest="$2"
  local name
  name=$(basename "$src")

  if [ -L "$dest" ]; then
    local current
    current=$(readlink "$dest")
    if [ "$current" = "$src" ]; then
      echo "  ○ $name (already linked)"
      SKIPPED=$((SKIPPED + 1))
      return
    fi
    # Different symlink target — update it
    rm "$dest"
  elif [ -f "$dest" ]; then
    # Regular file exists — back it up, then replace with symlink
    mv "$dest" "${dest}.bak"
    echo "  ⚠ $name (backed up existing file to ${name}.bak)"
  fi

  ln -sf "$src" "$dest"
  echo "  ✓ $name → $src"
  LINKED=$((LINKED + 1))
}

echo "→ Hooks (global)"
for f in "$REPO_ROOT"/hooks/global/*.sh; do
  [ -f "$f" ] || continue
  link_file "$f" "$HOOKS_DIR/$(basename "$f")"
done
echo ""

echo "→ Hooks (project)"
for f in "$REPO_ROOT"/hooks/project/*.sh; do
  [ -f "$f" ] || continue
  link_file "$f" "$HOOKS_DIR/$(basename "$f")"
done
echo ""

echo "→ Statusline"
for f in "$REPO_ROOT"/statusline/*.sh; do
  [ -f "$f" ] || continue
  link_file "$f" "$CLAUDE_DIR/$(basename "$f")"
done
echo ""

# --- Step 4: Summary ---
echo "================================="
echo "  ✓ Synced: $LINKED new/updated, $SKIPPED already linked"
echo "================================="
echo ""
echo "  Hooks live at: $HOOKS_DIR"
echo "  Source repo:   $REPO_ROOT"
echo ""
echo "  To update later: git pull in the repo (symlinks follow automatically)"
echo ""

# --- Step 5: Check settings.json references ---
# Warn if settings.json still uses relative paths or per-project paths
SETTINGS="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ]; then
  if grep -q 'bash .claude/hooks/' "$SETTINGS" 2>/dev/null; then
    echo "  ⚠ Your settings.json has relative hook paths (bash .claude/hooks/...)"
    echo "    Consider updating to: bash \"\$HOME/.claude/hooks/...\""
    echo "    This makes hooks work from any project without per-project copies."
    echo ""
  fi
fi
