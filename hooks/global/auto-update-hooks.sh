#!/bin/bash
# SessionStart hook: Auto-pull latest jmunch hooks from GitHub
# Since hooks are symlinked to the repo, git pull = instant update everywhere.
#
# Security:
#   - Verifies remote URL matches the expected GitHub repo
#   - Only fast-forward pulls (--ff-only) — rejects force-pushes
#   - Logs changed files so you know what updated
#   - Throttled to once per hour
#
# Install: Symlinked by sync-hooks.sh
# Register: SessionStart in ~/.claude/settings.json

# --- Config ---
# Users: set JMUNCH_REPO_DIR to override the default repo location
REPO_DIR="${JMUNCH_REPO_DIR:-$HOME/Development/AI/jmunch-claude-code-setup}"
EXPECTED_REMOTE="shacharbard/jmunch-claude-code-setup"
STAMP="/tmp/jmunch-auto-update-$(id -u)"
LOG="$HOME/.claude/jmunch-update.log"

# Throttle: skip if we pulled within the last hour
if [ -f "$STAMP" ]; then
  LAST=$(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  [ $((NOW - LAST)) -lt 3600 ] && exit 0
fi

# Skip if repo doesn't exist
[ -d "$REPO_DIR/.git" ] || exit 0

# Security: verify remote URL matches expected repo
REMOTE_URL=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "")
case "$REMOTE_URL" in
  *"$EXPECTED_REMOTE"*) ;;  # OK — matches expected repo
  *)
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED: remote URL '$REMOTE_URL' does not match expected '$EXPECTED_REMOTE'" >> "$LOG"
    exit 0
    ;;
esac

# Record pre-pull state
BEFORE=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)

# Fast-forward pull (rejects force-pushes, won't merge)
if git -C "$REPO_DIR" pull --ff-only --quiet 2>/dev/null; then
  touch "$STAMP"

  AFTER=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)

  # Log what changed (if anything)
  if [ "$BEFORE" != "$AFTER" ]; then
    {
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Updated: $BEFORE -> $AFTER"
      git -C "$REPO_DIR" diff --name-only "$BEFORE" "$AFTER" 2>/dev/null | sed 's/^/  /'
    } >> "$LOG"
  fi
fi

exit 0
