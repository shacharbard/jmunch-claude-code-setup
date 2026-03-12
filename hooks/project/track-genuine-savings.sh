#!/bin/bash
# PostToolUse hook: Track genuine token savings from jCodeMunch/jDocMunch
# Only counts tools where savings are real (symbol fetch, content slice, search)
# Skips optimistic tools (get_file_outline, get_repo_outline, get_file_tree, index_*)
#
# Writes to ~/.code-index/_genuine_savings.json
#
# Install: Copy to .claude/hooks/ in your project
# Register: PostToolUse matchers "mcp__jcodemunch__*" and "mcp__jdocmunch__*"
#           in project .claude/settings.json

INPUT=$(cat)

python3 -c "
import json, os, sys

savings_file = os.path.expanduser('$HOME/.code-index/_genuine_savings.json')
raw = sys.stdin.read()

try:
    d = json.loads(raw)
except:
    sys.exit(0)

tool_name = d.get('tool_name', '')

# Extract tokens_saved from response _meta
resp_list = d.get('tool_response', [])
tokens_saved = 0
for item in (resp_list if isinstance(resp_list, list) else []):
    if isinstance(item, dict):
        text = item.get('text', '')
        try:
            parsed = json.loads(text)
            meta = parsed.get('_meta', {})
            tokens_saved = meta.get('tokens_saved', 0)
        except:
            pass

if tokens_saved <= 0:
    sys.exit(0)

# Only count genuine tools
GENUINE_TOOLS = {
    'mcp__jcodemunch__get_symbol',
    'mcp__jcodemunch__get_symbols',
    'mcp__jcodemunch__search_symbols',
    'mcp__jcodemunch__search_text',
    'mcp__jdocmunch__get_section',
    'mcp__jdocmunch__get_sections',
    'mcp__jdocmunch__search_sections',
}

# get_file_content is genuine only with line ranges (sliced read)
if tool_name == 'mcp__jcodemunch__get_file_content':
    tool_input = d.get('tool_input', {})
    if isinstance(tool_input, str):
        try: tool_input = json.loads(tool_input)
        except: tool_input = {}
    if 'start_line' in tool_input or 'end_line' in tool_input:
        GENUINE_TOOLS.add('mcp__jcodemunch__get_file_content')

if tool_name not in GENUINE_TOOLS:
    sys.exit(0)

# Accumulate savings
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
" <<< "$INPUT"

exit 0
