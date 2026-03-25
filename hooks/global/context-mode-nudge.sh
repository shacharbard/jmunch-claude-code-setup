#!/bin/bash
# PreToolUse hook: Route Read on large JSON/HTML files to jDocMunch or context-mode
# Exit 2 = block with instruction to use jDocMunch or ctx_execute_file
# Exit 0 = allow (small files, config files, known exceptions)
#
# This hook complements jcodemunch-nudge.sh and jdocmunch-nudge.sh:
#   jcodemunch-nudge.sh  -> .py, .ts, .tsx  (code files)
#   jdocmunch-nudge.sh   -> .md, .mdx, .rst, .adoc, .ipynb, .xml, .svg, .xhtml (doc/structured files)
#   context-mode-nudge.sh -> .json, .html, .htm (smart routing: jDocMunch for structured, context-mode for data)
#
# Smart routing: JSON objects → jDocMunch, JSON arrays → context-mode
#                HTML with headings → jDocMunch, HTML without → context-mode

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path','') or d.get('file_path',''))" 2>/dev/null)

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

  # Resolve absolute path for ctx_execute_file (runs in temp sandbox)
  if [[ "$FILE_PATH" = /* ]]; then
    ABS_PATH="$FILE_PATH"
  else
    ABS_PATH="$(pwd)/$FILE_PATH"
  fi

  EXT="${BASENAME##*.}"

  # Smart routing: determine if jDocMunch or context-mode is the better target
  USE_JDOCMUNCH=false

  if [[ "$EXT" == "json" ]]; then
    # JSON: objects (starts with {) → jDocMunch, arrays (starts with [) → context-mode
    if [ -f "$FILE_PATH" ]; then
      FIRST_CHAR=$(python3 -c "
import sys
with open(sys.argv[1], 'r') as f:
    for line in f:
        s = line.strip()
        if s:
            print(s[0])
            break
" "$FILE_PATH" 2>/dev/null)
      if [[ "$FIRST_CHAR" == "{" ]]; then
        USE_JDOCMUNCH=true
      fi
    fi
  elif [[ "$EXT" == "html" || "$EXT" == "htm" ]]; then
    # HTML: files with heading tags → jDocMunch (doc-like), without → context-mode
    if [ -f "$FILE_PATH" ]; then
      if grep -qiE '<h[1-6][^>]*>' "$FILE_PATH" 2>/dev/null; then
        USE_JDOCMUNCH=true
      fi
    fi
  fi

  # If jDocMunch is the target, check that its index exists
  if [[ "$USE_JDOCMUNCH" == "true" ]]; then
    if [ ! -d "$HOME/.doc-index/local" ]; then
      # No jDocMunch index — fall back to context-mode
      USE_JDOCMUNCH=false
    fi
  fi

  if [[ "$USE_JDOCMUNCH" == "true" ]]; then
    # Route to jDocMunch
    if [[ "$EXT" == "json" ]]; then
      echo "BLOCKED: Large structured JSON file (${LINE_COUNT:-?} lines). Use jDocMunch instead of Read for '$BASENAME'.
  - Search: mcp__jdocmunch__search_sections(query=\"your search terms\")
  - Browse structure: mcp__jdocmunch__get_toc(path=\"$ABS_PATH\")
  - Get specific section: mcp__jdocmunch__get_section(section_id=\"...\")
  - Read is allowed for: config files (package.json, tsconfig.json), small files (<100 lines)" >&2
    else
      echo "BLOCKED: Large doc-like HTML file (${LINE_COUNT:-?} lines). Use jDocMunch instead of Read for '$BASENAME'.
  - Search: mcp__jdocmunch__search_sections(query=\"your search terms\")
  - Browse structure: mcp__jdocmunch__get_toc(path=\"$ABS_PATH\")
  - Get specific section: mcp__jdocmunch__get_section(section_id=\"...\")
  - Read is allowed for: small files (<100 lines)" >&2
    fi
    exit 2
  fi

  # Fallback: if context-mode is not configured in this project, allow Read
  CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
  if [ -n "$CWD" ]; then
    MCP_FILE="$CWD/.mcp.json"
  else
    MCP_FILE=".mcp.json"
  fi
  if [ ! -f "$MCP_FILE" ] || ! grep -q 'context-mode' "$MCP_FILE" 2>/dev/null; then
    # No context-mode available — only fall back to jDocMunch if the smart routing agreed
    if [[ "$USE_JDOCMUNCH" == "true" ]] && [ -d "$HOME/.doc-index/local" ]; then
      echo "BLOCKED: Large $EXT file (${LINE_COUNT:-?} lines). Use jDocMunch instead of Read for '$BASENAME'.
  - Search: mcp__jdocmunch__search_sections(query=\"your search terms\")
  - Browse structure: mcp__jdocmunch__get_toc(path=\"$ABS_PATH\")
  - Read is allowed for: config files (package.json, tsconfig.json), small files (<100 lines)" >&2
      exit 2
    fi
    exit 0
  fi

  # Route to context-mode
  # NOTE: ctx_execute_file injects file content as FILE_CONTENT variable (not sys.argv)
  if [[ "$EXT" == "json" ]]; then
    SUMMARY_HINT="Summarize: ctx_execute_file(path=\"$ABS_PATH\", language=\"python\", code=\"import json; data=json.loads(FILE_CONTENT); print(type(data).__name__, len(data) if isinstance(data,(list,dict)) else '?', 'entries'); print(json.dumps(data,indent=2)[:3000])\")"
  else
    SUMMARY_HINT="Summarize: ctx_execute_file(path=\"$ABS_PATH\", language=\"python\", code=\"import re; print(f'HTML: {len(FILE_CONTENT)} chars, {FILE_CONTENT.count(chr(10))} lines'); titles=re.findall(r'<(h[1-3])[^>]*>(.*?)</\\\\1>',FILE_CONTENT,re.I|re.S); [print(t[0],t[1].strip()[:80]) for t in titles[:20]]\")"
  fi

  echo "BLOCKED: Large $EXT file (${LINE_COUNT:-?} lines). Use context-mode instead of Read for '$BASENAME'.
  IMPORTANT: ctx_execute runs in a temp sandbox — always use ABSOLUTE paths.
  - $SUMMARY_HINT
  - Index by path: ctx_index(path=\"$ABS_PATH\", source=\"$BASENAME\")
  - Then search: ctx_search(queries=[\"your search terms\"])
  - Read is allowed for: config files (package.json, tsconfig.json), small files (<100 lines)" >&2
  exit 2
fi
