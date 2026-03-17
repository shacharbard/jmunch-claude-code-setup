#!/bin/bash
# sync-hooks.sh — Symlink all jmunch hooks to ~/.claude/hooks/
#
# Run from anywhere. Pulls latest from the repo, then creates symlinks
# so all projects use the same hooks. No more copying or chmod.
#
# Usage:
#   bash ~/Development/AI/jmunch-claude-code-setup/scripts/sync-hooks.sh
#   bash ~/Development/AI/jmunch-claude-code-setup/scripts/sync-hooks.sh --verify
#
# Options:
#   --verify    Verify file checksums against CHECKSUMS.sha256 after syncing
#
# What it does:
#   1. Verify remote URL matches expected GitHub repo
#   2. git pull --ff-only (rejects force-pushes)
#   3. Symlink hooks/global/*.sh and hooks/project/*.sh → ~/.claude/hooks/
#   4. Symlink statusline/*.sh → ~/.claude/
#   5. (--verify) Check SHA256 checksums of all files
#
# Security:
#   - Verifies git remote matches shacharbard/jmunch-claude-code-setup
#   - Only fast-forward pulls (rejects force-pushes and rebases)
#   - --verify checks file integrity against published checksums
#   - Backs up existing files before replacing
#
# After first run, updating is just: git pull in the repo.
# The symlinks point to the repo files, so changes are instant.

set -euo pipefail

VERIFY=false
for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY=true ;;
  esac
done

# Find the repo root (this script lives in scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HOOKS_DIR="$HOME/.claude/hooks"
CLAUDE_DIR="$HOME/.claude"
EXPECTED_REMOTE="shacharbard/jmunch-claude-code-setup"

echo "================================="
echo "  jmunch hook sync"
echo "================================="
echo ""
echo "  Repo: $REPO_ROOT"
echo ""

# --- Step 1: Verify remote + pull latest ---
if [ -d "$REPO_ROOT/.git" ]; then
  REMOTE_URL=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "")

  # Security: verify remote URL
  case "$REMOTE_URL" in
    *"$EXPECTED_REMOTE"*)
      echo "→ Remote: ✓ $EXPECTED_REMOTE"
      ;;
    "")
      echo "→ Remote: ○ No remote configured (local only)"
      ;;
    *)
      echo "→ Remote: ✗ UNEXPECTED: $REMOTE_URL"
      echo "  Expected: *$EXPECTED_REMOTE*"
      echo "  Aborting for safety. Verify you cloned the correct repo."
      exit 1
      ;;
  esac

  if [ -n "$REMOTE_URL" ]; then
    BEFORE=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)
    echo "→ Pulling latest (--ff-only)..."
    if git -C "$REPO_ROOT" pull --ff-only 2>&1; then
      AFTER=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)
      if [ "$BEFORE" != "$AFTER" ]; then
        echo "  ✓ Updated: $(git -C "$REPO_ROOT" log --oneline "$BEFORE".."$AFTER" | wc -l | tr -d ' ') new commit(s)"
        echo ""
        echo "  Changed files:"
        git -C "$REPO_ROOT" diff --name-only "$BEFORE" "$AFTER" 2>/dev/null | sed 's/^/    /'
      else
        echo "  ✓ Already up to date"
      fi
    else
      echo "  ⚠ Pull failed (continuing with local files)"
    fi
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

# --- Step 4: Verify checksums (if --verify) ---
if [ "$VERIFY" = true ]; then
  CHECKSUM_FILE="$REPO_ROOT/CHECKSUMS.sha256"
  if [ -f "$CHECKSUM_FILE" ]; then
    echo "→ Verifying checksums..."
    FAILURES=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      EXPECTED_HASH=$(echo "$line" | awk '{print $1}')
      FILE_PATH=$(echo "$line" | awk '{print $2}')
      FULL_PATH="$REPO_ROOT/$FILE_PATH"

      if [ ! -f "$FULL_PATH" ]; then
        echo "  ✗ $FILE_PATH (missing)"
        FAILURES=$((FAILURES + 1))
        continue
      fi

      ACTUAL_HASH=$(shasum -a 256 "$FULL_PATH" 2>/dev/null | awk '{print $1}')
      if [ "$ACTUAL_HASH" = "$EXPECTED_HASH" ]; then
        echo "  ✓ $FILE_PATH"
      else
        echo "  ✗ $FILE_PATH (CHECKSUM MISMATCH)"
        echo "    Expected: $EXPECTED_HASH"
        echo "    Actual:   $ACTUAL_HASH"
        FAILURES=$((FAILURES + 1))
      fi
    done < "$CHECKSUM_FILE"

    if [ "$FAILURES" -gt 0 ]; then
      echo ""
      echo "  ✗ $FAILURES file(s) failed verification!"
      echo "    Files may have been modified after the release."
      echo "    Run 'git diff' in the repo to inspect changes."
    else
      echo "  ✓ All files verified"
    fi
  else
    echo "→ ⚠ No CHECKSUMS.sha256 found — skipping verification"
  fi
  echo ""
fi

# --- Step 5: Summary ---
echo "================================="
echo "  ✓ Synced: $LINKED new/updated, $SKIPPED already linked"
echo "================================="
echo ""
echo "  Hooks live at: $HOOKS_DIR"
echo "  Source repo:   $REPO_ROOT"
echo ""
echo "  To update later: git pull in the repo (symlinks follow automatically)"
echo "  To verify:       bash $SCRIPT_DIR/sync-hooks.sh --verify"
echo ""

# --- Step 6: Check settings.json references ---
SETTINGS="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ]; then
  if grep -q 'bash .claude/hooks/' "$SETTINGS" 2>/dev/null; then
    echo "  ⚠ Your settings.json has relative hook paths (bash .claude/hooks/...)"
    echo "    Consider updating to: bash \"\$HOME/.claude/hooks/...\""
    echo "    This makes hooks work from any project without per-project copies."
    echo ""
  fi
fi
