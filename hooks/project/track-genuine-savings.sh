#!/bin/bash
# PostToolUse hook: Track genuine token savings from jCodeMunch/jDocMunch
# Only counts tools where savings are real (symbol fetch, content slice, search)
# Skips optimistic tools (get_file_outline, get_repo_outline, get_file_tree, index_*)
#
# For jDocMunch tools that report tokens_saved=0 (search_sections returns summaries),
# estimates savings as: baseline_tokens - actual_output_tokens
#
# Writes to ~/.code-index/_genuine_savings.json + _genuine_savings_history.jsonl
#
# Install: Copy to .claude/hooks/ in your project
# Register: PostToolUse matchers "mcp__jcodemunch__*" and "mcp__jdocmunch__*"
#           in project .claude/settings.json

INPUT=$(cat)

python3 -c "
import json, os, sys, datetime

agent_suffix = '_' + os.environ.get('CLAUDE_AGENT_NAME', '') if os.environ.get('CLAUDE_AGENT_NAME') else ''
savings_file = os.path.expanduser(os.environ.get('HOME', '~') + '/.code-index/_genuine_savings' + agent_suffix + '.json')
raw = sys.stdin.read()

try:
    d = json.loads(raw)
except:
    sys.exit(0)

tool_name = d.get('tool_name', '')

# Only count genuine tools
GENUINE_TOOLS = {
    'mcp__jcodemunch__get_symbol',
    'mcp__jcodemunch__get_symbols',
    'mcp__jcodemunch__search_symbols',
    'mcp__jcodemunch__search_text',
    'mcp__jdocmunch__get_section',
    'mcp__jdocmunch__get_sections',
    'mcp__jdocmunch__get_section_context',
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

# For jDocMunch tools that report tokens_saved=0, estimate savings
# (search_sections returns summaries — small response, but replaces a full file Read)
if tokens_saved <= 0 and tool_name.startswith('mcp__jdocmunch__'):
    # Measure actual output size
    output_text = ''.join(
        item.get('text', '') for item in (resp_list if isinstance(resp_list, list) else [])
        if isinstance(item, dict)
    )
    output_tokens = len(output_text.encode('utf-8')) // 4

    # Estimate baseline: what a full Read would have cost
    # Conservative baselines per tool type
    BASELINE_TOKENS = {
        'mcp__jdocmunch__search_sections': 8000,    # ~32KB avg doc file
        'mcp__jdocmunch__get_section': 4000,         # ~16KB avg doc (section is subset)
        'mcp__jdocmunch__get_sections': 8000,        # batch retrieval
        'mcp__jdocmunch__get_section_context': 5000,  # section + ancestors
    }
    baseline = BASELINE_TOKENS.get(tool_name, 5000)
    tokens_saved = max(0, baseline - output_tokens)

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
log_file = os.path.expanduser(os.environ.get('HOME', '~') + '/.code-index/_genuine_savings_history.jsonl')
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
