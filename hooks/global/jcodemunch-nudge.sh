#!/bin/bash
# PreToolUse hook: BLOCK Read on code files — enforce jCodeMunch usage
# Exit 2 = block the tool call with message shown to the model
# Exit 0 = allow (non-code files, small files, explicit exceptions)
#
# Install: Copy to ~/.claude/hooks/ or .claude/hooks/
# Register: PreToolUse matcher "Read" in settings.json

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)

# Check if file is a code type supported by jCodeMunch (40+ languages)
is_code_file() {
  case "$1" in
    *.py|*.ts|*.tsx|*.js|*.jsx|*.go|*.rs|*.java|*.php|*.dart|*.cs|*.c|*.cpp|*.h|*.hpp|\
    *.swift|*.ex|*.exs|*.rb|*.pl|*.pm|*.gd|*.kt|*.scala|*.hs|*.jl|*.r|*.R|*.lua|*.sh|\
    *.css|*.sql|*.vue|*.groovy|*.m|*.proto|*.hcl|*.graphql|*.nix|*.asm|*.toml|*.xml)
      return 0 ;;
    *) return 1 ;;
  esac
}

if is_code_file "$FILE_PATH"; then
  BASENAME=$(basename "$FILE_PATH")

  # Allow exceptions: config-like files, test fixtures
  if [[ "$BASENAME" == "CLAUDE.md" || "$BASENAME" == "conftest.py" ]]; then
    exit 0
  fi

  # Allow files in non-code directories (config, docs, planning)
  if [[ "$FILE_PATH" == */.vbw-planning/* || "$FILE_PATH" == */.planning/* || "$FILE_PATH" == */.claude/* ]]; then
    exit 0
  fi

  # Fallback: if jCodeMunch is not configured in this project, allow Read
  # Check for .mcp.json with jcodemunch, or project hooks with session gate
  CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
  if [ -n "$CWD" ]; then
    MCP_FILE="$CWD/.mcp.json"
  else
    MCP_FILE=".mcp.json"
  fi
  if [ ! -f "$MCP_FILE" ] || ! grep -q 'jcodemunch' "$MCP_FILE" 2>/dev/null; then
    exit 0
  fi

  # Block with instruction to use jCodeMunch
  echo "BLOCKED: Use jCodeMunch instead of Read for '$BASENAME'.
  - Understand a function: mcp__jcodemunch__get_symbol
  - Find by name: mcp__jcodemunch__search_symbols (skip outline)
  - Edit a function: get_symbol (find line range) -> get_file_content(start_line=line-4, end_line=end_line+3) -> Edit
  - Full Read ONLY when: editing 6+ functions in same file, need imports/globals, or file <50 lines" >&2
  exit 2
fi
