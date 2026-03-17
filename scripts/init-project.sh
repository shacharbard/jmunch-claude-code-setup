#!/bin/bash
# init-project.sh — Set up jmunch enforcement in a new project
#
# Run from the root of any project to enable jCodeMunch/jDocMunch enforcement.
# Creates symlinks, MCP config, tool permissions, and hook registrations.
#
# Usage:
#   bash ~/Development/AI/jmunch-claude-code-setup/scripts/init-project.sh
#
# What it does:
#   1. Symlinks hooks from ~/.claude/hooks/ into .claude/hooks/
#   2. Creates .mcp.json (jcodemunch + jdocmunch servers)
#   3. Creates/updates .claude/settings.local.json (tool permissions)
#   4. Creates/updates .claude/settings.json (hook registrations)
#
# Safe to re-run — skips files that already exist, backs up before overwriting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(pwd)"
GLOBAL_HOOKS="$HOME/.claude/hooks"

echo "================================="
echo "  jmunch project init"
echo "================================="
echo ""
echo "  Project: $PROJECT_DIR"
echo "  Repo:    $REPO_ROOT"
echo ""

# --- Guard: don't init inside the setup repo itself ---
if [ "$PROJECT_DIR" = "$REPO_ROOT" ]; then
  echo "  ✗ You're inside the setup repo itself. Run this from a project directory."
  exit 1
fi

# --- Guard: check global hooks exist ---
if [ ! -L "$GLOBAL_HOOKS/jmunch-session-gate.sh" ] && [ ! -f "$GLOBAL_HOOKS/jmunch-session-gate.sh" ]; then
  echo "  ✗ Global hooks not found. Run sync-hooks.sh first:"
  echo "    bash $REPO_ROOT/scripts/sync-hooks.sh"
  exit 1
fi

# --- Step 1: Symlink hooks ---
echo "→ Hooks"
mkdir -p .claude/hooks

HOOKS=(
  jmunch-session-start.sh
  jmunch-session-gate.sh
  jmunch-sentinel-writer.sh
  agent-jcodemunch-gate.sh
  jcodemunch-nudge.sh
  jdocmunch-nudge.sh
  reindex-after-edit.sh
  reindex-after-commit.sh
  track-genuine-savings.sh
)

for hook in "${HOOKS[@]}"; do
  DEST=".claude/hooks/$hook"
  if [ -L "$DEST" ]; then
    echo "  ○ $hook (already linked)"
  elif [ -f "$DEST" ]; then
    mv "$DEST" "${DEST}.bak"
    ln -sf "$GLOBAL_HOOKS/$hook" "$DEST"
    echo "  ✓ $hook → $GLOBAL_HOOKS/$hook (old file backed up)"
  else
    ln -sf "$GLOBAL_HOOKS/$hook" "$DEST"
    echo "  ✓ $hook → $GLOBAL_HOOKS/$hook"
  fi
done
echo ""

# --- Step 2: MCP config ---
echo "→ MCP config (.mcp.json)"
if [ -f .mcp.json ]; then
  # Check if jcodemunch is already configured
  if jq -e '.mcpServers.jcodemunch' .mcp.json >/dev/null 2>&1; then
    echo "  ○ .mcp.json already has jcodemunch configured"
  else
    echo "  ⚠ .mcp.json exists but missing jcodemunch — merge manually from:"
    echo "    $REPO_ROOT/rules/mcp-example.json"
  fi
else
  cp "$REPO_ROOT/rules/mcp-example.json" .mcp.json
  echo "  ✓ .mcp.json created (jcodemunch + jdocmunch + context-mode)"
fi
echo ""

# --- Step 3: Tool permissions ---
echo "→ Tool permissions (.claude/settings.local.json)"
mkdir -p .claude
if [ -f .claude/settings.local.json ]; then
  echo "  ○ .claude/settings.local.json already exists"
  # Check if MCP tools are already allowed
  if jq -e '.permissions.allow[]?' .claude/settings.local.json 2>/dev/null | grep -q 'mcp__jcodemunch' 2>/dev/null; then
    echo "    (jcodemunch tools already in allowlist)"
  else
    echo "  ⚠ Consider adding MCP tools to allowlist. See:"
    echo "    $REPO_ROOT/rules/allowed-tools.txt"
  fi
else
  # Build settings.local.json with MCP tool permissions
  TOOLS_JSON=$(grep -v '^#' "$REPO_ROOT/rules/allowed-tools.txt" | grep -v '^$' | jq -R . | jq -s .)
  jq -n \
    --argjson tools "$TOOLS_JSON" \
    '{
      "permissions": { "allow": $tools },
      "enabledMcpjsonServers": ["jcodemunch", "jdocmunch"]
    }' > .claude/settings.local.json
  echo "  ✓ .claude/settings.local.json created (MCP tools allowed)"
fi
echo ""

# --- Step 4: Hook registrations ---
echo "→ Hook registrations (.claude/settings.json)"
if [ -f .claude/settings.json ]; then
  # Check if session gate is already registered
  if grep -q 'jmunch-session-gate' .claude/settings.json 2>/dev/null; then
    echo "  ○ .claude/settings.json already has jmunch hooks registered"
  else
    echo "  ⚠ .claude/settings.json exists but missing jmunch hooks"
    echo "    Merge hooks from: $REPO_ROOT/rules/project-settings-example.json"
  fi
else
  # Create settings.json with all hook registrations
  cat > .claude/settings.json << 'SETTINGS'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/jmunch-session-start.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/jmunch-session-gate.sh"
          }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/jcodemunch-nudge.sh"
          },
          {
            "type": "command",
            "command": "bash .claude/hooks/jdocmunch-nudge.sh"
          }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/agent-jcodemunch-gate.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__jcodemunch__index_folder",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/jmunch-sentinel-writer.sh"
          }
        ]
      },
      {
        "matcher": "mcp__jdocmunch__index_local",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/jmunch-sentinel-writer.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/reindex-after-commit.sh"
          }
        ]
      },
      {
        "matcher": "mcp__jcodemunch__*",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/track-genuine-savings.sh"
          }
        ]
      },
      {
        "matcher": "mcp__jdocmunch__*",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/track-genuine-savings.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS
  echo "  ✓ .claude/settings.json created (all hooks registered)"
fi
echo ""

# --- Summary ---
echo "================================="
echo "  ✓ Project initialized"
echo "================================="
echo ""
echo "  Next: Start a Claude Code session in this project."
echo "  The session gate will enforce jCodeMunch/jDocMunch usage."
echo ""
echo "  Files created:"
echo "    .claude/hooks/         → symlinks to global hooks"
echo "    .claude/settings.json  → hook registrations"
echo "    .claude/settings.local.json → MCP tool permissions"
echo "    .mcp.json              → MCP server config"
echo ""
