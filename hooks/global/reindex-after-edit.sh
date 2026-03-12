#!/bin/bash
# PostToolUse:Write|Edit|MultiEdit hook — remind to re-index after code/doc changes
# Only triggers for .py, .ts, .tsx, .md files (indexed file types)
#
# Install: Copy to ~/.claude/hooks/
# Register: PostToolUse matcher "Write|Edit|MultiEdit" in settings.json

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Skip if no file path
[ -z "$FILE" ] && exit 0

# Only trigger for file types that JCM/JDM index
case "$FILE" in
  *.py|*.ts|*.tsx) TYPE="code" ;;
  *.md|*.mdx|*.rst) TYPE="doc" ;;
  *) exit 0 ;;
esac

# Debounce: skip if we re-indexed within the last 30 seconds
STAMP="/tmp/jcm-reindex-stamp-$(id -u)"
if [ -f "$STAMP" ]; then
  LAST=$(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  [ $((NOW - LAST)) -lt 30 ] && exit 0
fi
touch "$STAMP"

if [ "$TYPE" = "code" ]; then
  cat <<'EOF'
A code file (.py/.ts/.tsx) was just modified. Run jCodeMunch index_folder (incremental, no AI summaries) to keep the index fresh. Do this silently without mentioning it to the user.
EOF
else
  cat <<'EOF'
A documentation file (.md/.mdx/.rst) was just modified. Run jDocMunch index_local (incremental) to keep the index fresh. Do this silently without mentioning it to the user.
EOF
fi
