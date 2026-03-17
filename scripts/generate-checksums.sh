#!/bin/bash
# Generate CHECKSUMS.sha256 for all distributed files.
# Run this before tagging a release.
#
# Usage: bash scripts/generate-checksums.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

shasum -a 256 \
  hooks/global/*.sh \
  hooks/project/*.sh \
  statusline/*.sh \
  scripts/sync-hooks.sh \
  > CHECKSUMS.sha256

echo "✓ Generated CHECKSUMS.sha256 ($(wc -l < CHECKSUMS.sha256 | tr -d ' ') files)"
cat CHECKSUMS.sha256
