#!/bin/bash
# Double-click to prepare and push a release.
#
# What it does:
#   1. Regenerates CHECKSUMS.sha256
#   2. Runs sync-hooks.sh --verify to confirm integrity
#   3. Shows what changed since last tag
#   4. Asks for a version tag (e.g., v1.0.0)
#   5. Commits checksums, tags the release, pushes everything

set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

echo "================================="
echo "  jmunch-claude-code-setup"
echo "  Release Prep"
echo "================================="
echo ""

# --- Step 1: Regenerate checksums ---
echo "→ Regenerating checksums..."
bash scripts/generate-checksums.sh
echo ""

# --- Step 2: Verify ---
echo "→ Verifying all files..."
FAILURES=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  EXPECTED=$(echo "$line" | awk '{print $1}')
  FILE=$(echo "$line" | awk '{print $2}')
  ACTUAL=$(shasum -a 256 "$FILE" 2>/dev/null | awk '{print $1}')
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "  ✓ $FILE"
  else
    echo "  ✗ $FILE (MISMATCH)"
    FAILURES=$((FAILURES + 1))
  fi
done < CHECKSUMS.sha256

if [ "$FAILURES" -gt 0 ]; then
  echo ""
  echo "  ✗ Verification failed! Aborting."
  echo ""
  echo "Press any key to close..."
  read -n 1
  exit 1
fi
echo "  ✓ All files verified"
echo ""

# --- Step 3: Show changes since last tag ---
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$LAST_TAG" ]; then
  echo "→ Changes since $LAST_TAG:"
  git log --oneline "$LAST_TAG"..HEAD
else
  echo "→ All commits (no previous tags):"
  git log --oneline -10
fi
echo ""

# --- Step 4: Ask for version ---
echo "→ Enter version tag (e.g., v1.0.0):"
read -r VERSION

if [ -z "$VERSION" ]; then
  echo "  ✗ No version entered. Aborting."
  echo ""
  echo "Press any key to close..."
  read -n 1
  exit 1
fi

# Validate format
if ! echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "  ⚠ '$VERSION' doesn't match vX.Y.Z format. Continue anyway? (y/n)"
  read -n 1 CONFIRM
  echo ""
  if [ "$CONFIRM" != "y" ]; then
    echo "  Aborting."
    echo ""
    echo "Press any key to close..."
    read -n 1
    exit 1
  fi
fi

# --- Step 5: Commit, tag, push ---
echo ""
echo "→ Committing checksums..."
git add CHECKSUMS.sha256
if git diff --cached --quiet; then
  echo "  ○ No checksum changes to commit"
else
  git commit -m "release: update checksums for $VERSION"
  echo "  ✓ Committed"
fi

echo "→ Tagging $VERSION..."
git tag -a "$VERSION" -m "Release $VERSION"
echo "  ✓ Tagged"

echo "→ Pushing..."
git push && git push --tags
echo "  ✓ Pushed"

echo ""
echo "================================="
echo "  ✓ Released $VERSION"
echo "================================="
echo ""
echo "  Users will auto-update on next session start."
echo "  They can verify with: sync-hooks.sh --verify"
echo ""
echo "Press any key to close..."
read -n 1
