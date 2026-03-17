#!/bin/bash
# SessionStart hook: Auto-pull latest jmunch hooks from GitHub
# Since hooks are symlinked to the repo, git pull = instant update everywhere.
#
# Security:
#   - Verifies remote URL matches the expected GitHub repo
#   - Only fast-forward pulls (--ff-only) — rejects force-pushes
#   - Logs changed files so you know what updated
#   - Throttled to once per hour
#   - Status messages only printed AFTER a real check (never stale data)
#
# Install: Symlinked by sync-hooks.sh
# Register: SessionStart in ~/.claude/settings.json

# --- Config ---
# Users: set JMUNCH_REPO_DIR to override the default repo location
# Users: set JMUNCH_BRANCH to track a different branch (default: stable)
REPO_DIR="${JMUNCH_REPO_DIR:-$HOME/Development/AI/jmunch-claude-code-setup}"
BRANCH="${JMUNCH_BRANCH:-stable}"
EXPECTED_REMOTE="shacharbard/jmunch-claude-code-setup"
STAMP="/tmp/jmunch-auto-update-$(id -u)"
LOG="$HOME/.claude/jmunch-update.log"

# Throttle: skip entirely if we checked within the last hour
# No status message — we only report after a real check
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

# Ensure we're on the right branch
CURRENT_BRANCH=$(git -C "$REPO_DIR" branch --show-current 2>/dev/null)
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
  git -C "$REPO_DIR" checkout "$BRANCH" --quiet 2>/dev/null || exit 0
fi

# Record pre-pull state
BEFORE=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)

# Fast-forward pull (rejects force-pushes, won't merge)
if git -C "$REPO_DIR" pull --ff-only --quiet 2>/dev/null; then
  touch "$STAMP"

  AFTER=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)
  SHORT_AFTER=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null)
  LATEST_TAG=$(git -C "$REPO_DIR" describe --tags --abbrev=0 2>/dev/null || echo "untagged")

  if [ "$BEFORE" != "$AFTER" ]; then
    # Updated — log and notify
    COMMIT_COUNT=$(git -C "$REPO_DIR" rev-list "$BEFORE".."$AFTER" --count 2>/dev/null || echo "?")
    {
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Updated: $BEFORE -> $AFTER"
      git -C "$REPO_DIR" diff --name-only "$BEFORE" "$AFTER" 2>/dev/null | sed 's/^/  /'
    } >> "$LOG"
    echo "jmunch hooks updated ($COMMIT_COUNT new commit(s) on $BRANCH, now at $SHORT_AFTER). Tell the user: \"jmunch hooks updated to $SHORT_AFTER ($COMMIT_COUNT new commit(s) on $BRANCH).\""
  else
    # Verified up to date — we actually checked the remote
    echo "jmunch hooks verified up to date ($BRANCH @ $SHORT_AFTER, $LATEST_TAG). Tell the user: \"jmunch hooks verified up to date ($BRANCH @ $SHORT_AFTER, $LATEST_TAG).\""
  fi
else
  # Pull failed
  SHORT_HEAD=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null)
  echo "jmunch hooks pull failed (currently on $BRANCH @ $SHORT_HEAD). Tell the user: \"jmunch hooks pull failed — using $BRANCH @ $SHORT_HEAD.\""
fi

exit 0
