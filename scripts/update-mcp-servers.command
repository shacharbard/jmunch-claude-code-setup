#!/bin/bash

echo "================================="
echo "  Updating MCP Servers"
echo "================================="
echo ""

# Load nvm (needed for npm/npx)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Load uv/uvx
export PATH="$HOME/.local/bin:$PATH"

FAILURES=0

# --- jCodeMunch ---
echo "→ jCodeMunch"
OLD_VER=$(jcodemunch-mcp --version 2>/dev/null || echo "unknown")
echo "  Before: $OLD_VER"
if uv tool upgrade jcodemunch-mcp 2>&1; then
  NEW_VER=$(jcodemunch-mcp --version 2>/dev/null || echo "unknown")
  echo "  After:  $NEW_VER  ✓"
else
  echo "  ✗ UPDATE FAILED"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- jDocMunch ---
echo "→ jDocMunch"
OLD_VER=$(jdocmunch-mcp --version 2>/dev/null || echo "unknown")
echo "  Before: $OLD_VER"
if uv tool upgrade jdocmunch-mcp 2>&1; then
  NEW_VER=$(jdocmunch-mcp --version 2>/dev/null || echo "unknown")
  echo "  After:  $NEW_VER  ✓"
else
  echo "  ✗ UPDATE FAILED"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- context-mode ---
echo "→ context-mode"
OLD_VER=$(npm list -g context-mode --depth=0 2>/dev/null | grep context-mode || echo "unknown")
echo "  Before: $OLD_VER"
if npm update -g context-mode 2>&1; then
  NEW_VER=$(npm list -g context-mode --depth=0 2>/dev/null | grep context-mode || echo "unknown")
  echo "  After:  $NEW_VER  ✓"
else
  echo "  ✗ UPDATE FAILED"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Summary ---
echo "================================="
if [ $FAILURES -eq 0 ]; then
  echo "  ✓ All 3 MCP servers updated!"
else
  echo "  ✗ $FAILURES update(s) failed — check errors above"
fi
echo "================================="
echo ""
echo "Press any key to close..."
read -n 1
