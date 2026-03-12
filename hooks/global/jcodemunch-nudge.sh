#!/bin/bash
# PreToolUse hook: BLOCK Read on code files — enforce jCodeMunch usage
# Exit 2 = block the tool call with message shown to the model
# Exit 0 = allow (non-code files, small files, explicit exceptions)
#
# Install: Copy to ~/.claude/hooks/ or .claude/hooks/
# Register: PreToolUse matcher "Read" in settings.json

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)

# Only enforce for Python and TypeScript code files
if [[ "$FILE_PATH" == *.py || "$FILE_PATH" == *.ts || "$FILE_PATH" == *.tsx ]]; then
  BASENAME=$(basename "$FILE_PATH")

  # Allow exceptions: config-like files, test fixtures
  if [[ "$BASENAME" == "CLAUDE.md" || "$BASENAME" == "conftest.py" ]]; then
    exit 0
  fi

  # Allow files in non-code directories (config, docs, planning)
  if [[ "$FILE_PATH" == */.vbw-planning/* || "$FILE_PATH" == */.planning/* || "$FILE_PATH" == */.claude/* ]]; then
    exit 0
  fi

  # Fallback: if jCodeMunch index doesn't exist, allow Read (MCP server may be down)
  # NOTE: Replace the index path below with your project's actual index file.
  # Run `mcp__jcodemunch__list_repos` to find your repo ID, then check:
  #   ~/.code-index/<repo-id>.json
  # if [ ! -f "$HOME/.code-index/<your-repo-id>.json" ]; then
  #   echo "jCodeMunch index not found — allowing Read as fallback."
  #   exit 0
  # fi

  # Block with instruction to use jCodeMunch
  echo "BLOCKED: Use jCodeMunch instead of Read for '$BASENAME'.
  - Understand a function: mcp__jcodemunch__get_symbol
  - Find by name: mcp__jcodemunch__search_symbols (skip outline)
  - Edit a function: get_symbol (find line range) -> get_file_content(start_line=line-4, end_line=end_line+3) -> Edit
  - Full Read ONLY when: editing 6+ functions in same file, need imports/globals, or file <50 lines"
  exit 2
fi
