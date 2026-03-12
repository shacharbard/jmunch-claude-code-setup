#!/bin/bash
# SessionStart hook — instruct the LLM to reindex jCodeMunch + jDocMunch
# before doing anything else. Output becomes a system prompt injection.
#
# Install: Copy to .claude/hooks/ in your project
# Register: SessionStart in project .claude/settings.json
#
# Paired with: jmunch-session-gate.sh (blocks tools until indexes are ready)
#              jmunch-sentinel-writer.sh (marks indexes as ready)

SENTINEL="/tmp/jmunch-session-ready-${PPID}"

# Clean up stale sentinel from any previous session with same PID
rm -f "$SENTINEL"

cat <<'PROMPT'
**MANDATORY FIRST ACTION — do this BEFORE responding to the user:**

1. Fetch the tool schemas: `ToolSearch("select:mcp__jcodemunch__index_folder,mcp__jdocmunch__index_local")`
2. Run BOTH in parallel:
   - `mcp__jcodemunch__index_folder(path=".", incremental=true, use_ai_summaries=false)`
   - `mcp__jdocmunch__index_local(path=".", use_ai_summaries=false)`
3. After both complete, tell the user: "jCodeMunch + jDocMunch indexes refreshed." Then proceed with whatever the user asked.

Do NOT skip this. Do NOT respond to the user first. Index refresh is the very first thing you do.
PROMPT
