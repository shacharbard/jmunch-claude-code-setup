#!/bin/bash
# SubagentStart hook: Inject jCodeMunch/jDocMunch tracking instructions into subagents
#
# Subagents don't inherit hook instructions, so they miss MCP navigation rules.
# This hook injects the core rules via additionalContext so subagents prefer
# jCodeMunch/jDocMunch over raw Read/Grep/Glob.
#
# Install: Symlink to ~/.claude/hooks/ via sync-hooks.sh
# Register: SubagentStart (no matcher = all subagents) in ~/.claude/settings.json

cat <<'HOOK_OUTPUT'
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "## jCodeMunch/jDocMunch Navigation Rules\nWhen mcp__jcodemunch__* and mcp__jdocmunch__* tools are available, ALWAYS prefer them over Read/Grep/Glob for code and doc navigation.\n- Use get_symbol for specific functions/classes — NEVER read entire files for one symbol\n- Use search_symbols instead of Grep for function/class definitions\n- Use search_sections/get_section for documentation files\n- These MCP tools save 85-95% of tokens compared to raw file reads\n- If mcp__jcodemunch__index_folder is available, run it with incremental=true at the start of your work"
  }
}
HOOK_OUTPUT

exit 0
