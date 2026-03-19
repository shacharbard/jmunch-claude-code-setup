#!/bin/bash
# jmunch-claude-code-setup installer
#
# One-liner install:
#   curl -sSL https://raw.githubusercontent.com/shacharbard/jmunch-claude-code-setup/stable/install.sh | bash
#
# What it does:
#   1. Clones the repo to ~/.jmunch-hooks (or updates if already cloned)
#   2. Symlinks all hooks to ~/.claude/hooks/
#   3. Verifies checksums
#   4. Registers the auto-update hook in ~/.claude/settings.json
#
# To also set up a specific project:
#   curl -sSL https://raw.githubusercontent.com/shacharbard/jmunch-claude-code-setup/stable/install.sh | bash -s -- --project /path/to/project
#
# Prerequisites:
#   - git, jq, python3, bc
#   - uv tool install jcodemunch-mcp jdocmunch-mcp

set -euo pipefail

REPO_URL="https://github.com/shacharbard/jmunch-claude-code-setup.git"
INSTALL_DIR="$HOME/.jmunch-hooks"
BRANCH="stable"
CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
PROJECT_DIR=""

# Parse args
for arg in "$@"; do
  case "$arg" in
    --project=*) PROJECT_DIR="${arg#--project=}" ;;
    --project) ;; # next arg is the path
    --main) BRANCH="main" ;;
    *)
      # Capture path after --project
      if [ "${PREV_ARG:-}" = "--project" ]; then
        PROJECT_DIR="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

echo ""
echo "================================="
echo "  jmunch-claude-code-setup"
echo "  Installer"
echo "================================="
echo ""

# --- Step 1: Check prerequisites ---
echo "→ Checking prerequisites..."
MISSING=0
for cmd in git jq python3; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $cmd"
  else
    echo "  ✗ $cmd (required)"
    MISSING=$((MISSING + 1))
  fi
done

if ! command -v jcodemunch-mcp >/dev/null 2>&1; then
  echo "  ⚠ jcodemunch-mcp not found — install with: uv tool install jcodemunch-mcp"
fi
if ! command -v jdocmunch-mcp >/dev/null 2>&1; then
  echo "  ⚠ jdocmunch-mcp not found — install with: uv tool install jdocmunch-mcp"
fi
if ! command -v context-mode >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
  echo "  ⚠ context-mode not found — install with: npm install -g context-mode"
fi
if ! command -v muninndb-lite >/dev/null 2>&1; then
  echo "  ⚠ muninndb-lite not found — install with: curl -fsSL https://raw.githubusercontent.com/Aperrix/muninndb-lite/develop/install.sh | sh"
fi

if [ "$MISSING" -gt 0 ]; then
  echo ""
  echo "  ✗ Missing $MISSING required tool(s). Install them and re-run."
  exit 1
fi
echo ""

# --- Step 2: Clone or update repo ---
echo "→ Installing to $INSTALL_DIR ($BRANCH branch)..."
if [ -d "$INSTALL_DIR/.git" ]; then
  # Already cloned — update
  cd "$INSTALL_DIR"
  CURRENT=$(git branch --show-current 2>/dev/null)
  if [ "$CURRENT" != "$BRANCH" ]; then
    git checkout "$BRANCH" --quiet 2>/dev/null
  fi
  if git pull --ff-only --quiet 2>/dev/null; then
    echo "  ✓ Updated to latest"
  else
    echo "  ⚠ Pull failed (using existing files)"
  fi
else
  # Fresh clone
  git clone --branch "$BRANCH" --quiet "$REPO_URL" "$INSTALL_DIR"
  echo "  ✓ Cloned ($BRANCH branch)"
fi
echo ""

# --- Step 3: Symlink hooks ---
echo "→ Symlinking hooks to $HOOKS_DIR..."
mkdir -p "$HOOKS_DIR"

LINKED=0
SKIPPED=0

link_hook() {
  local src="$1"
  local dest="$2"
  local name
  name=$(basename "$src")

  if [ -L "$dest" ]; then
    local current
    current=$(readlink "$dest")
    if [ "$current" = "$src" ]; then
      SKIPPED=$((SKIPPED + 1))
      return
    fi
    rm "$dest"
  elif [ -f "$dest" ]; then
    mv "$dest" "${dest}.bak"
    echo "  ⚠ $name (backed up existing file)"
  fi

  ln -sf "$src" "$dest"
  LINKED=$((LINKED + 1))
}

for f in "$INSTALL_DIR"/hooks/global/*.sh "$INSTALL_DIR"/hooks/project/*.sh; do
  [ -f "$f" ] || continue
  link_hook "$f" "$HOOKS_DIR/$(basename "$f")"
done

for f in "$INSTALL_DIR"/statusline/*.sh; do
  [ -f "$f" ] || continue
  link_hook "$f" "$CLAUDE_DIR/$(basename "$f")"
done

echo "  ✓ $LINKED linked, $SKIPPED already up to date"
echo ""

# --- Step 4: Verify checksums ---
echo "→ Verifying checksums..."
CHECKSUM_FILE="$INSTALL_DIR/CHECKSUMS.sha256"
if [ -f "$CHECKSUM_FILE" ]; then
  FAILURES=0
  CHECKED=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    EXPECTED=$(echo "$line" | awk '{print $1}')
    FILE=$(echo "$line" | awk '{print $2}')
    FULL="$INSTALL_DIR/$FILE"
    [ -f "$FULL" ] || continue
    ACTUAL=$(shasum -a 256 "$FULL" 2>/dev/null | awk '{print $1}')
    if [ "$ACTUAL" != "$EXPECTED" ]; then
      echo "  ✗ $FILE (CHECKSUM MISMATCH)"
      FAILURES=$((FAILURES + 1))
    fi
    CHECKED=$((CHECKED + 1))
  done < "$CHECKSUM_FILE"

  if [ "$FAILURES" -gt 0 ]; then
    echo "  ✗ $FAILURES file(s) failed verification!"
    exit 1
  fi
  echo "  ✓ All $CHECKED files verified"
else
  echo "  ⚠ No CHECKSUMS.sha256 found — skipping"
fi
echo ""

# --- Step 5: Register auto-update in global settings ---
echo "→ Registering auto-update hook..."
mkdir -p "$CLAUDE_DIR"
SETTINGS="$CLAUDE_DIR/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

# Check if auto-update is already registered
if grep -q 'auto-update-hooks.sh' "$SETTINGS" 2>/dev/null; then
  echo "  ○ Already registered in settings.json"
else
  # Add the auto-update hook to SessionStart
  UPDATED=$(jq '
    .hooks.SessionStart = (
      [{"hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/auto-update-hooks.sh\"", "timeout": 10}]}]
      + (.hooks.SessionStart // [])
    )
  ' "$SETTINGS")
  echo "$UPDATED" > "$SETTINGS"
  echo "  ✓ Auto-update hook added to settings.json"
fi
echo ""

# --- Step 6: Init project (if --project) ---
if [ -n "$PROJECT_DIR" ]; then
  echo "→ Initializing project: $PROJECT_DIR"
  if [ -d "$PROJECT_DIR" ]; then
    (cd "$PROJECT_DIR" && bash "$INSTALL_DIR/scripts/init-project.sh")
  else
    echo "  ✗ Directory not found: $PROJECT_DIR"
  fi
  echo ""
fi

# --- Summary ---
echo "================================="
echo "  ✓ Installation complete"
echo "================================="
echo ""
echo "  Hooks installed to: $HOOKS_DIR"
echo "  Source repo:         $INSTALL_DIR"
echo "  Branch:              $BRANCH"
echo "  Auto-update:         every session (throttled to 1x/hour)"
echo ""
echo "  To set up a project:"
echo "    cd /path/to/your/project"
echo "    bash $INSTALL_DIR/scripts/init-project.sh"
echo ""
echo "  To verify integrity:"
echo "    bash $INSTALL_DIR/scripts/sync-hooks.sh --verify"
echo ""
