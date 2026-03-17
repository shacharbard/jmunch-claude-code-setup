#!/bin/bash
# SessionStart hook: Auto-pull latest jmunch hooks from GitHub
# Since hooks are symlinked to the repo, git pull = instant update everywhere.
#
# Throttled to once per hour to avoid slowing down session starts.
#
# Install: Symlinked by sync-hooks.sh
# Register: SessionStart in ~/.claude/settings.json

REPO_DIR="$HOME/Development/AI/jmunch-claude-code-setup"
STAMP="/tmp/jmunch-auto-update-$(id -u)"

# Throttle: skip if we pulled within the last hour
if [ -f "$STAMP" ]; then
  LAST=$(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  [ $((NOW - LAST)) -lt 3600 ] && exit 0
fi

# Skip if repo doesn't exist
[ -d "$REPO_DIR/.git" ] || exit 0

# Fast-forward pull (non-destructive, won't fail on local changes)
if git -C "$REPO_DIR" pull --ff-only --quiet 2>/dev/null; then
  touch "$STAMP"
fi

exit 0
