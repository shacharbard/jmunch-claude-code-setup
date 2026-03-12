#!/bin/bash
# PreToolUse hook on Agent: BLOCK agent spawning if prompt doesn't include
# jCodeMunch/jDocMunch instructions as appropriate for the agent type.
# Exit 2 = block with message | Exit 0 = allow
#
# KEY FEATURE: The error message includes the FULL correct instructions
# so Claude can copy them verbatim on retry — no memory lookup needed.
#
# Install: Copy to .claude/hooks/ in your project
# Register: PreToolUse matcher "Agent" in project .claude/settings.json
#
# CUSTOMIZATION: Update the Repo IDs in the BLOCK messages below to match
# your project. Run `mcp__jcodemunch__list_repos` and `mcp__jdocmunch__list_repos`
# to find your repo IDs.

INPUT=$(cat)

# Extract prompt and subagent_type from Agent tool input
eval "$(echo "$INPUT" | python3 -c "
import sys, json, shlex
try:
    d = json.load(sys.stdin)
    print(f'PROMPT={shlex.quote(d.get(\"prompt\", \"\"))}')
    print(f'SUBAGENT_TYPE={shlex.quote(d.get(\"subagent_type\", \"\"))}')
except:
    print('PROMPT=\"\"')
    print('SUBAGENT_TYPE=\"\"')
" 2>/dev/null)"

# If no prompt found, allow (might be a resume or non-standard call)
if [ -z "$PROMPT" ]; then
  exit 0
fi

# Classify agent type:
#   code-agents: need jCodeMunch (+ jDocMunch)
#   doc-agents: need jDocMunch only
#   exempt: no MCP requirements (pure web search, guide, etc.)
case "$SUBAGENT_TYPE" in
  claude-code-guide)
    # Pure help agent — no codebase access needed
    exit 0
    ;;
  vbw-scout|Explore|researcher|vbw-docs)
    # Doc-heavy agents: require jDocMunch but not jCodeMunch
    if echo "$PROMPT" | grep -qi "jdocmunch\|mcp__jdocmunch\|search_sections\|get_section"; then
      exit 0
    fi
    cat <<'BLOCK_MSG'
BLOCKED: Agent prompt must include jDocMunch instructions. Copy these VERBATIM into your agent prompt:

**Doc navigation (MANDATORY):** Use jDocMunch MCP tools for documentation files.
- Use mcp__jdocmunch__search_sections to find relevant doc sections
- Use mcp__jdocmunch__get_section for specific content by section ID
- Fall back to Read ONLY for small docs (<50 lines) or planning files
BLOCK_MSG
    exit 2
    ;;
  *)
    # Code-touching agents (dev, lead, qa, debugger, coder, reviewer, etc.)
    # Require BOTH jCodeMunch and jDocMunch
    HAS_CODE=$(echo "$PROMPT" | grep -qi "jcodemunch\|mcp__jcodemunch\|get_symbol\|search_symbols\|get_file_outline" && echo "yes" || echo "no")
    HAS_DOCS=$(echo "$PROMPT" | grep -qi "jdocmunch\|mcp__jdocmunch\|search_sections\|get_section" && echo "yes" || echo "no")

    if [ "$HAS_CODE" = "yes" ] && [ "$HAS_DOCS" = "yes" ]; then
      exit 0
    fi

    # Build the block message with FULL instructions for copy-paste retry
    BLOCK_HEADER="BLOCKED: Agent prompt missing"
    [ "$HAS_CODE" = "no" ] && [ "$HAS_DOCS" = "no" ] && BLOCK_HEADER="$BLOCK_HEADER jCodeMunch AND jDocMunch"
    [ "$HAS_CODE" = "no" ] && [ "$HAS_DOCS" = "yes" ] && BLOCK_HEADER="$BLOCK_HEADER jCodeMunch"
    [ "$HAS_CODE" = "yes" ] && [ "$HAS_DOCS" = "no" ] && BLOCK_HEADER="$BLOCK_HEADER jDocMunch"
    BLOCK_HEADER="$BLOCK_HEADER instructions. Copy the missing block(s) VERBATIM into your agent prompt:"

    echo "$BLOCK_HEADER"
    echo ""

    if [ "$HAS_CODE" = "no" ]; then
      cat <<'CODE_INSTRUCTIONS'
**Code navigation (MANDATORY):** Use jCodeMunch MCP tools for all Python/TypeScript code exploration.
- Use mcp__jcodemunch__get_symbol to fetch specific functions/classes — NEVER read an entire .py/.ts/.tsx file to find one function
- Use mcp__jcodemunch__search_symbols instead of Grep for function/class definitions (1 call, skip outline)
- **Sliced edit workflow:** To edit a function: get_symbol (find line range) -> get_file_content(start_line=line-4, end_line=end_line+3) -> Edit. Do NOT read the full file.
- Full Read only when: editing 6+ functions in same file, need imports/globals, file <50 lines, non-code files
CODE_INSTRUCTIONS
    fi

    if [ "$HAS_DOCS" = "no" ]; then
      cat <<'DOC_INSTRUCTIONS'
**Doc navigation (MANDATORY):** Use jDocMunch MCP tools for documentation files.
- Use mcp__jdocmunch__search_sections to find relevant doc sections
- Use mcp__jdocmunch__get_section for specific content by section ID
- Fall back to Read ONLY for small docs (<50 lines) or planning files
DOC_INSTRUCTIONS
    fi

    exit 2
    ;;
esac
