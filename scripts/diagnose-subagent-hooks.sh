#!/bin/bash
# diagnose-subagent-hooks.sh — Check whether PostToolUse hooks fire for subagent MCP calls
#
# Examines JSONL history files and savings JSON files to determine if subagent
# tool calls are being tracked by the PostToolUse hooks.
#
# Usage:
#   bash scripts/diagnose-subagent-hooks.sh

set -euo pipefail

CODE_INDEX="$HOME/.code-index"
DOC_INDEX="$HOME/.doc-index"
SETTINGS="$HOME/.claude/settings.json"
HOOKS_DIR="$HOME/.claude/hooks"

echo "================================="
echo "  Subagent Hook Diagnostic"
echo "================================="
echo ""

# --- 1. Check JSONL history files ---
echo "→ JSONL History Entries"
for INDEX_DIR in "$CODE_INDEX" "$DOC_INDEX"; do
  LABEL=$(basename "$INDEX_DIR")
  HISTORY="$INDEX_DIR/_genuine_savings_history.jsonl"
  if [ -f "$HISTORY" ]; then
    TOTAL=$(wc -l < "$HISTORY" | tr -d ' ')
    # Count entries with vs without agent_name
    MAIN_COUNT=$(python3 -c "
import json, sys
count = 0
for line in open('$HISTORY'):
    try:
        d = json.loads(line.strip())
        name = d.get('agent_name', '')
        if not name:
            count += 1
    except: pass
print(count)
" 2>/dev/null || echo "?")
    AGENT_COUNT=$(python3 -c "
import json, sys
agents = {}
for line in open('$HISTORY'):
    try:
        d = json.loads(line.strip())
        name = d.get('agent_name', '')
        if name:
            agents[name] = agents.get(name, 0) + 1
    except: pass
if agents:
    for k,v in sorted(agents.items()):
        print(f'  {k}: {v}')
else:
    print('  (none)')
" 2>/dev/null || echo "  ?")
    echo "  $LABEL: $TOTAL total entries"
    echo "    Main agent: $MAIN_COUNT"
    echo "    Subagents:"
    echo "$AGENT_COUNT"
  else
    echo "  $LABEL: no history file found"
  fi
done
echo ""

# --- 2. Check agent-suffixed savings files ---
echo "→ Agent-Suffixed Savings Files"
FOUND_AGENT_FILES=false
for INDEX_DIR in "$CODE_INDEX" "$DOC_INDEX"; do
  LABEL=$(basename "$INDEX_DIR")
  for f in "$INDEX_DIR"/_genuine_savings_*.json; do
    [ -f "$f" ] || continue
    BASENAME=$(basename "$f")
    # Skip the main (non-suffixed) file
    if [ "$BASENAME" = "_genuine_savings.json" ]; then
      continue
    fi
    FOUND_AGENT_FILES=true
    echo "  $LABEL/$BASENAME"
  done
done
if [ "$FOUND_AGENT_FILES" = false ]; then
  echo "  (none found — CLAUDE_AGENT_NAME suffix logic never triggered)"
fi
echo ""

# --- 3. Check SubagentStart hook registration ---
echo "→ SubagentStart Hook Registration"
if [ -f "$SETTINGS" ]; then
  if python3 -c "
import json, sys
with open('$SETTINGS') as f:
    s = json.load(f)
hooks = s.get('hooks', {})
if 'SubagentStart' in hooks:
    entries = hooks['SubagentStart']
    print(f'  Registered: {len(entries)} entry/entries')
    for e in entries:
        for h in e.get('hooks', []):
            cmd = h.get('command', h.get('prompt', '(prompt hook)'))
            print(f'    - {cmd}')
    sys.exit(0)
print('  NOT registered')
sys.exit(0)
" 2>/dev/null; then
    :
  else
    echo "  Error reading settings"
  fi
else
  echo "  $SETTINGS not found"
fi
echo ""

# --- 4. Check PostToolUse hook registration ---
echo "→ PostToolUse Hook Registration"
if [ -f "$SETTINGS" ]; then
  if python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
hooks = s.get('hooks', {}).get('PostToolUse', [])
if not hooks:
    print('  NOT registered')
else:
    for entry in hooks:
        matcher = entry.get('matcher', '(no matcher — all tools)')
        for h in entry.get('hooks', []):
            cmd = h.get('command', '(prompt)')
            print(f'  [{matcher}] {cmd}')
" 2>/dev/null; then
    :
  else
    echo "  Error reading settings"
  fi
else
  echo "  $SETTINGS not found"
fi
echo ""

# --- 5. Compare server-side savings vs hook-tracked totals ---
echo "→ Savings Comparison (server-side vs hook-tracked)"
for INDEX_DIR in "$CODE_INDEX" "$DOC_INDEX"; do
  LABEL=$(basename "$INDEX_DIR")
  SAVINGS_FILE="$INDEX_DIR/_genuine_savings.json"
  HISTORY="$INDEX_DIR/_genuine_savings_history.jsonl"

  if [ -f "$SAVINGS_FILE" ]; then
    HOOK_TOTAL=$(python3 -c "
import json
with open('$SAVINGS_FILE') as f:
    d = json.load(f)
print(d.get('total_tokens_saved', 0))
" 2>/dev/null || echo "?")
    echo "  $LABEL hook-tracked total: $HOOK_TOTAL tokens saved"
  else
    echo "  $LABEL: no _genuine_savings.json"
  fi

  if [ -f "$HISTORY" ]; then
    HISTORY_TOTAL=$(python3 -c "
import json
total = 0
for line in open('$HISTORY'):
    try:
        d = json.loads(line.strip())
        total += d.get('tokens_saved', 0)
    except: pass
print(total)
" 2>/dev/null || echo "?")
    echo "  $LABEL history total:       $HISTORY_TOTAL tokens saved"
  fi
done
echo ""

# --- 6. Diagnostic summary ---
echo "================================="
echo "  Diagnostic Summary"
echo "================================="
echo ""

# Check if subagent-inject hook file exists
if [ -L "$HOOKS_DIR/subagent-inject-mcp-tracking.sh" ] || [ -f "$HOOKS_DIR/subagent-inject-mcp-tracking.sh" ]; then
  echo "  ✓ SubagentStart hook file exists in ~/.claude/hooks/"
else
  echo "  ✗ SubagentStart hook file NOT found in ~/.claude/hooks/"
  echo "    Run: bash scripts/sync-hooks.sh"
fi

if [ -f "$SETTINGS" ] && python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
assert 'SubagentStart' in s.get('hooks', {})
" 2>/dev/null; then
  echo "  ✓ SubagentStart registered in settings.json"
else
  echo "  ✗ SubagentStart NOT registered in settings.json"
fi

echo ""
echo "  Key question: Do PostToolUse hooks fire for subagent tool calls?"
echo "  If subagent JSONL entries = 0 but subagents definitely used MCP tools,"
echo "  then PostToolUse hooks do NOT fire for subagent tool calls."
echo "  The SubagentStart hook injects instructions as a workaround."
echo ""
