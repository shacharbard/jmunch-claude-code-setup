#!/bin/bash
# init-project.sh — Set up jmunch enforcement in a new project
#
# Run from the root of any project to enable jCodeMunch/jDocMunch enforcement.
# Creates symlinks, MCP config, tool permissions, and hook registrations.
#
# Usage:
#   bash ~/.jmunch-hooks/scripts/init-project.sh                  # jCodeMunch + jDocMunch only
#   bash ~/.jmunch-hooks/scripts/init-project.sh --context-mode   # + context-mode enforcement
#   bash ~/.jmunch-hooks/scripts/init-project.sh --muninn         # + MuninnDB cross-session memory
#   bash ~/.jmunch-hooks/scripts/init-project.sh --context-mode --muninn  # full stack
#
# What it does:
#   1. Symlinks hooks from ~/.claude/hooks/ into .claude/hooks/
#   2. Creates .mcp.json (jcodemunch + jdocmunch, optionally context-mode)
#   3. Creates/updates .claude/settings.local.json (tool permissions)
#   4. Creates/updates .claude/settings.json (hook registrations)
#
# Safe to re-run — skips files that already exist, backs up before overwriting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(pwd)"
GLOBAL_HOOKS="$HOME/.claude/hooks"
ENABLE_CTX=false
ENABLE_MUNINN=false

# Parse args
for arg in "$@"; do
  case "$arg" in
    --context-mode) ENABLE_CTX=true ;;
    --muninn) ENABLE_MUNINN=true ;;
  esac
done

echo "================================="
echo "  jmunch project init"
echo "================================="
echo ""
echo "  Project: $PROJECT_DIR"
echo "  Context-mode: $([ "$ENABLE_CTX" = true ] && echo "enabled" || echo "disabled (use --context-mode to enable)")"
echo "  MuninnDB:     $([ "$ENABLE_MUNINN" = true ] && echo "enabled" || echo "disabled (use --muninn to enable)")"
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

if [ "$ENABLE_CTX" = true ]; then
  HOOKS+=(
    context-mode-nudge.sh
    context-mode-bash-nudge.sh
    track-genuine-savings-ctx.sh
  )
fi

for hook in "${HOOKS[@]}"; do
  DEST=".claude/hooks/$hook"
  if [ -L "$DEST" ]; then
    echo "  ○ $hook (already linked)"
  elif [ -f "$DEST" ]; then
    mv "$DEST" "${DEST}.bak"
    ln -sf "$GLOBAL_HOOKS/$hook" "$DEST"
    echo "  ✓ $hook (old file backed up)"
  else
    ln -sf "$GLOBAL_HOOKS/$hook" "$DEST"
    echo "  ✓ $hook"
  fi
done
echo ""

# --- Step 2: MCP config ---
echo "→ MCP config (.mcp.json)"
if [ -f .mcp.json ]; then
  if jq -e '.mcpServers.jcodemunch' .mcp.json >/dev/null 2>&1; then
    echo "  ○ .mcp.json already has jcodemunch configured"
  else
    echo "  ⚠ .mcp.json exists but missing jcodemunch — merge manually from:"
    echo "    $REPO_ROOT/rules/mcp-example.json"
  fi
  # Add context-mode if enabled and missing
  if [ "$ENABLE_CTX" = true ]; then
    if jq -e '.mcpServers."context-mode"' .mcp.json >/dev/null 2>&1; then
      echo "  ○ .mcp.json already has context-mode configured"
    else
      jq '.mcpServers["context-mode"] = {"type":"stdio","command":"npx","args":["-y","context-mode"]}' .mcp.json > .mcp.json.tmp && mv .mcp.json.tmp .mcp.json
      echo "  ✓ Added context-mode to .mcp.json"
    fi
  fi
  # Add muninn if enabled and missing
  if [ "$ENABLE_MUNINN" = true ]; then
    if jq -e '.mcpServers.muninn' "$HOME/.claude/.mcp.json" >/dev/null 2>&1; then
      echo "  ○ MuninnDB already configured globally in ~/.claude/.mcp.json — skipping per-project config"
    elif jq -e '.mcpServers.muninn' .mcp.json >/dev/null 2>&1; then
      echo "  ○ .mcp.json already has muninn configured"
    else
      jq '.mcpServers.muninn = {"command":"muninndb-lite","args":["mcp"],"type":"stdio"}' .mcp.json > .mcp.json.tmp && mv .mcp.json.tmp .mcp.json
      echo "  ✓ Added muninn to .mcp.json"
    fi
  fi
else
  # Start from the full example, then strip what's not enabled
  cp "$REPO_ROOT/rules/mcp-example.json" .mcp.json
  COMPONENTS="jcodemunch + jdocmunch"
  if [ "$ENABLE_CTX" != true ]; then
    jq 'del(.mcpServers["context-mode"])' .mcp.json > .mcp.json.tmp && mv .mcp.json.tmp .mcp.json
  else
    COMPONENTS="$COMPONENTS + context-mode"
  fi
  if [ "$ENABLE_MUNINN" != true ]; then
    jq 'del(.mcpServers.muninn)' .mcp.json > .mcp.json.tmp && mv .mcp.json.tmp .mcp.json
  elif jq -e '.mcpServers.muninn' "$HOME/.claude/.mcp.json" >/dev/null 2>&1; then
    jq 'del(.mcpServers.muninn)' .mcp.json > .mcp.json.tmp && mv .mcp.json.tmp .mcp.json
    echo "  ○ MuninnDB already configured globally in ~/.claude/.mcp.json — skipping per-project config"
  else
    COMPONENTS="$COMPONENTS + muninn"
  fi
  echo "  ✓ .mcp.json created ($COMPONENTS)"
fi
echo ""

# --- Step 3: Tool permissions ---
echo "→ Tool permissions (.claude/settings.local.json)"
mkdir -p .claude
if [ -f .claude/settings.local.json ]; then
  echo "  ○ .claude/settings.local.json already exists"
  if jq -e '.permissions.allow[]?' .claude/settings.local.json 2>/dev/null | grep -q 'mcp__jcodemunch' 2>/dev/null; then
    echo "    (jcodemunch tools already in allowlist)"
  else
    echo "  ⚠ Consider adding MCP tools to allowlist. See:"
    echo "    $REPO_ROOT/rules/allowed-tools.txt"
  fi
else
  TOOLS_JSON=$(grep -v '^#' "$REPO_ROOT/rules/allowed-tools.txt" | grep -v '^$' | jq -R . | jq -s .)
  SERVERS='["jcodemunch", "jdocmunch"]'
  if [ "$ENABLE_CTX" = true ]; then
    SERVERS=$(echo "$SERVERS" | jq '. + ["context-mode"]')
  fi
  if [ "$ENABLE_MUNINN" = true ]; then
    SERVERS=$(echo "$SERVERS" | jq '. + ["muninn"]')
  fi
  jq -n \
    --argjson tools "$TOOLS_JSON" \
    --argjson servers "$SERVERS" \
    '{
      "permissions": { "allow": $tools },
      "enabledMcpjsonServers": $servers
    }' > .claude/settings.local.json
  echo "  ✓ .claude/settings.local.json created"
fi
echo ""

# --- Step 4: Hook registrations ---
echo "→ Hook registrations (.claude/settings.json)"
if [ -f .claude/settings.json ]; then
  if grep -q 'jmunch-session-gate' .claude/settings.json 2>/dev/null; then
    echo "  ○ .claude/settings.json already has jmunch hooks registered"
  else
    echo "  ⚠ .claude/settings.json exists but missing jmunch hooks"
    echo "    Merge hooks from: $REPO_ROOT/rules/project-settings-example.json"
  fi
else
  # Build context-mode hook entries
  CTX_READ_HOOKS=""
  CTX_BASH_HOOKS=""
  CTX_POST_HOOKS=""
  if [ "$ENABLE_CTX" = true ]; then
    CTX_READ_HOOKS=',
          {
            "type": "command",
            "command": "bash .claude/hooks/context-mode-nudge.sh"
          }'
    CTX_BASH_HOOKS=',
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/context-mode-bash-nudge.sh"
          }
        ]
      }'
    CTX_POST_HOOKS=',
      {
        "matcher": "mcp__context-mode__*",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/track-genuine-savings-ctx.sh"
          }
        ]
      }'
  fi

  cat > .claude/settings.json << SETTINGS
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
          }${CTX_READ_HOOKS}
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
      }${CTX_BASH_HOOKS}
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
      }${CTX_POST_HOOKS}
    ]
  }
}
SETTINGS
  echo "  ✓ .claude/settings.json created"
fi
echo ""

# --- Summary ---
echo "================================="
echo "  ✓ Project initialized"
echo "================================="
echo ""
echo "  Enforcement:"
echo "    ✓ jCodeMunch (code files: .py/.ts/.tsx)"
echo "    ✓ jDocMunch  (doc files: .md/.mdx/.rst)"
if [ "$ENABLE_CTX" = true ]; then
echo "    ✓ context-mode (data files: .json/.html, command outputs)"
else
echo "    ○ context-mode (disabled — re-run with --context-mode to enable)"
fi
if [ "$ENABLE_MUNINN" = true ]; then
echo "    ✓ MuninnDB    (cross-session memory)"
else
echo "    ○ MuninnDB    (disabled — re-run with --muninn to enable)"
fi
echo ""
echo "  Next: Start a Claude Code session in this project."
echo ""
