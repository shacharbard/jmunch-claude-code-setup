#!/bin/bash
# PostToolUse hook: Track genuine token savings from context-mode
# Since context-mode doesn't report tokens_saved in _meta (unlike jCodeMunch),
# we compute savings as: estimated_input_tokens - output_tokens
#
# For ctx_execute_file: uses actual file size from tool_input.path
# For ctx_execute/ctx_batch_execute: uses conservative baselines
#
# Writes to ~/.code-index/_genuine_savings_ctx.json
# Register: PostToolUse matcher "mcp__context-mode__*" in settings.json

INPUT=$(cat)

python3 -c "
import json, os, sys

savings_file = os.path.expanduser(os.environ.get('HOME', '~') + '/.code-index/_genuine_savings_ctx.json')

try:
    d = json.loads(sys.stdin.read())
except:
    sys.exit(0)

tool_name = d.get('tool_name', '')

# Only count genuine tools (actually replace a Read or Bash)
GENUINE_TOOLS = {
    'mcp__context-mode__ctx_execute',
    'mcp__context-mode__ctx_execute_file',
    'mcp__context-mode__ctx_batch_execute',
    'mcp__context-mode__ctx_fetch_and_index',
}

if tool_name not in GENUINE_TOOLS:
    sys.exit(0)

# For ctx_execute, only count shell commands (not python one-liners etc.)
tool_input = d.get('tool_input', {})
if isinstance(tool_input, str):
    try:
        tool_input = json.loads(tool_input)
    except:
        tool_input = {}

if tool_name == 'mcp__context-mode__ctx_execute':
    lang = tool_input.get('language', '')
    if lang != 'shell':
        sys.exit(0)  # Non-shell ctx_execute is not a Bash replacement

# Measure output size (what actually entered context)
resp_list = d.get('tool_response', [])
if isinstance(resp_list, str):
    try:
        resp_list = json.loads(resp_list)
    except:
        resp_list = []

output_text = ''.join(
    item.get('text', '') for item in (resp_list if isinstance(resp_list, list) else [])
    if isinstance(item, dict)
)
output_bytes = len(output_text.encode('utf-8'))
output_tokens = output_bytes // 4

# Estimate baseline tokens (what WOULD have entered context without sandboxing)
# Conservative fixed baselines from context-mode documentation
BASELINE_TOKENS = {
    'mcp__context-mode__ctx_execute': 14000,        # ~56KB avg bash output
    'mcp__context-mode__ctx_execute_file': 11250,    # ~45KB avg file
    'mcp__context-mode__ctx_batch_execute': 60000,   # ~240KB (conservative)
    'mcp__context-mode__ctx_fetch_and_index': 8000,  # ~32KB avg fetched page
}

# For ctx_execute_file: use actual file size when available (more accurate)
if tool_name == 'mcp__context-mode__ctx_execute_file':
    file_path = tool_input.get('path', '')
    if file_path and os.path.exists(file_path):
        actual_bytes = os.path.getsize(file_path)
        baseline_tokens = actual_bytes // 4
    else:
        baseline_tokens = BASELINE_TOKENS[tool_name]
else:
    baseline_tokens = BASELINE_TOKENS[tool_name]

tokens_saved = max(0, baseline_tokens - output_tokens)

if tokens_saved <= 0:
    sys.exit(0)

# Accumulate savings
os.makedirs(os.path.dirname(savings_file), exist_ok=True)
try:
    data = json.loads(open(savings_file).read()) if os.path.exists(savings_file) else {}
except:
    data = {}

data['total_genuine_tokens_saved'] = data.get('total_genuine_tokens_saved', 0) + tokens_saved

by_tool = data.get('by_tool', {})
by_tool[tool_name] = by_tool.get(tool_name, 0) + tokens_saved
data['by_tool'] = by_tool

calls = data.get('call_counts', {})
calls[tool_name] = calls.get(tool_name, 0) + 1
data['call_counts'] = calls

with open(savings_file, 'w') as f:
    json.dump(data, f, indent=2)

# Append to JSONL history log (one line per savings event)
import datetime
log_file = os.path.expanduser(os.environ.get('HOME', '~') + '/.code-index/_genuine_savings_ctx_history.jsonl')
entry = {
    'ts': datetime.datetime.utcnow().isoformat() + 'Z',
    'agent': os.environ.get('CLAUDE_AGENT_NAME', ''),
    'tool': tool_name,
    'tokens_saved': tokens_saved,
    'cumulative': data['total_genuine_tokens_saved'],
}
with open(log_file, 'a') as f:
    f.write(json.dumps(entry) + '\n')
" <<< "$INPUT"

exit 0
