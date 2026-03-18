#!/bin/bash
# PreToolUse hook: BLOCK Read on large doc files — enforce jDocMunch usage
# Exit 2 = block the tool call with message shown to the model
# Exit 0 = allow (small files, instruction files, non-doc files)
#
# Install: Copy to ~/.claude/hooks/ or .claude/hooks/
# Register: PreToolUse matcher "Read" in settings.json

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)

# Only enforce for documentation and structured files
# Note: .json, .html, .htm are handled by context-mode-nudge.sh with smart routing
if [[ "$FILE_PATH" == *.md || "$FILE_PATH" == *.mdx || "$FILE_PATH" == *.rst || \
      "$FILE_PATH" == *.adoc || "$FILE_PATH" == *.asc || "$FILE_PATH" == *.asciidoc || \
      "$FILE_PATH" == *.ipynb || "$FILE_PATH" == *.xml || "$FILE_PATH" == *.svg || \
      "$FILE_PATH" == *.xhtml ]]; then
  BASENAME=$(basename "$FILE_PATH")

  # Always allow instruction/config files that should be read fully
  if [[ "$BASENAME" == "CLAUDE.md" || "$BASENAME" == "MEMORY.md" || "$BASENAME" == "README.md" ]]; then
    exit 0
  fi

  # Allow planning files (STATE.md, ROADMAP.md, PLAN.md, SUMMARY.md, etc.)
  if [[ "$FILE_PATH" == */.vbw-planning/* || "$FILE_PATH" == */.planning/* || "$FILE_PATH" == *-PLAN.md || "$FILE_PATH" == *-SUMMARY.md || "$FILE_PATH" == *-UAT.md || "$FILE_PATH" == *-CONTEXT.md ]]; then
    exit 0
  fi

  # Allow small files (< 50 lines)
  if [ -f "$FILE_PATH" ]; then
    LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null)
    if [ "$LINE_COUNT" -lt 50 ] 2>/dev/null; then
      exit 0
    fi
  fi

  # Fallback: if jDocMunch index doesn't exist, allow Read
  if [ ! -d "$HOME/.doc-index/local" ]; then
    echo "jDocMunch index not found — allowing Read as fallback. Run mcp__jdocmunch__index_local to re-enable enforcement."
    exit 0
  fi

  # Block with instruction to use jDocMunch
  echo "BLOCKED: Use jDocMunch instead of Read for '$BASENAME' (${LINE_COUNT:-unknown} lines). Use mcp__jdocmunch__search_sections to find relevant sections, mcp__jdocmunch__get_section for specific content by ID. Read is only allowed for small docs (<50 lines), CLAUDE.md, or planning files." >&2
  exit 2
fi
