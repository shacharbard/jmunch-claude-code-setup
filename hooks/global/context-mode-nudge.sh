#!/bin/bash
# PreToolUse hook: Route Read on large JSON/HTML files to context-mode
# Exit 2 = block with instruction to use ctx_execute_file
# Exit 0 = allow (small files, config files, known exceptions)
#
# This hook complements jcodemunch-nudge.sh and jdocmunch-nudge.sh:
#   jcodemunch-nudge.sh  -> .py, .ts, .tsx  (code files)
#   jdocmunch-nudge.sh   -> .md, .mdx, .rst (doc files)
#   context-mode-nudge.sh -> .json, .html, .htm (data files)
#
# No overlapping extensions. No conflicts.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)

# Only enforce for JSON and HTML files
if [[ "$FILE_PATH" == *.json || "$FILE_PATH" == *.html || "$FILE_PATH" == *.htm ]]; then
  BASENAME=$(basename "$FILE_PATH")

  # Always allow small config files that should be read directly
  if [[ "$BASENAME" == "package.json" || \
        "$BASENAME" == "package-lock.json" || \
        "$BASENAME" == "tsconfig.json" || \
        "$BASENAME" == tsconfig.*.json || \
        "$BASENAME" == ".eslintrc.json" || \
        "$BASENAME" == "components.json" || \
        "$BASENAME" == "plugin.json" || \
        "$BASENAME" == "marketplace.json" || \
        "$BASENAME" == "config.json" || \
        "$BASENAME" == "manifest.json" || \
        "$BASENAME" == ".mcp.json" || \
        "$BASENAME" == "mcp.json" ]]; then
    exit 0
  fi

  # Allow planning/config/node_modules directories
  if [[ "$FILE_PATH" == */.vbw-planning/* || \
        "$FILE_PATH" == */.planning/* || \
        "$FILE_PATH" == */.claude/* || \
        "$FILE_PATH" == */node_modules/* ]]; then
    exit 0
  fi

  # Allow small files (< 100 lines for JSON/HTML)
  if [ -f "$FILE_PATH" ]; then
    LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null)
    if [ "$LINE_COUNT" -lt 100 ] 2>/dev/null; then
      exit 0
    fi
  fi

  # Fallback: if context-mode is not configured in this project, allow Read
  CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
  if [ -n "$CWD" ]; then
    MCP_FILE="$CWD/.mcp.json"
  else
    MCP_FILE=".mcp.json"
  fi
  if [ ! -f "$MCP_FILE" ] || ! grep -q 'context-mode' "$MCP_FILE" 2>/dev/null; then
    exit 0
  fi

  # Resolve absolute path for ctx_execute_file (runs in temp sandbox)
  if [[ "$FILE_PATH" = /* ]]; then
    ABS_PATH="$FILE_PATH"
  else
    ABS_PATH="$(pwd)/$FILE_PATH"
  fi

  # Build file-type-specific instructions with absolute paths
  # NOTE: ctx_execute_file injects file content as FILE_CONTENT variable (not sys.argv)
  EXT="${BASENAME##*.}"
  if [[ "$EXT" == "json" ]]; then
    SUMMARY_HINT="Summarize: ctx_execute_file(path=\"$ABS_PATH\", language=\"python\", code=\"import json; data=json.loads(FILE_CONTENT); print(type(data).__name__, len(data) if isinstance(data,(list,dict)) else '?', 'entries'); print(json.dumps(data,indent=2)[:3000])\")"
  else
    SUMMARY_HINT="Summarize: ctx_execute_file(path=\"$ABS_PATH\", language=\"python\", code=\"import re; print(f'HTML: {len(FILE_CONTENT)} chars, {FILE_CONTENT.count(chr(10))} lines'); titles=re.findall(r'<(h[1-3])[^>]*>(.*?)</\\\\1>',FILE_CONTENT,re.I|re.S); [print(t[0],t[1].strip()[:80]) for t in titles[:20]]\")"
  fi

  # Block with instruction to use context-mode
  echo "BLOCKED: Large $EXT file (${LINE_COUNT:-?} lines). Use context-mode instead of Read for '$BASENAME'.
  IMPORTANT: ctx_execute runs in a temp sandbox — always use ABSOLUTE paths.
  - $SUMMARY_HINT
  - Index by path: ctx_index(path=\"$ABS_PATH\", source=\"$BASENAME\")
  - Then search: ctx_search(queries=[\"your search terms\"])
  - Read is allowed for: config files (package.json, tsconfig.json), small files (<100 lines)"
  exit 2
fi
