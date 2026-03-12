# jCodeMunch + jDocMunch Setup for Claude Code

Hooks, rules, and statusline integration for [jCodeMunch](https://github.com/jgravelle/jcodemunch-mcp) and [jDocMunch](https://github.com/jgravelle/jdocmunch-mcp) — two excellent MCP servers created by [J. Gravelle (jgravelle)](https://github.com/jgravelle) that dramatically reduce token usage in Claude Code.

> **Credit where it's due:** jCodeMunch and jDocMunch are built and maintained by [J. Gravelle](https://github.com/jgravelle). This repo does not contain those MCP servers — it provides a companion enforcement and tracking layer that helps Claude Code get the most out of them. All the clever indexing and symbol extraction is jgravelle's work.

## What jCodeMunch & jDocMunch Do

- **[jCodeMunch](https://github.com/jgravelle/jcodemunch-mcp)** (by jgravelle) indexes your code (Python, TypeScript) so Claude fetches individual functions instead of reading entire files. Saves ~85-95% of tokens on code exploration.
- **[jDocMunch](https://github.com/jgravelle/jdocmunch-mcp)** (by jgravelle) indexes your docs (.md, .mdx, .rst) so Claude fetches specific sections instead of entire documents. Saves ~90-95% on doc lookups.

This repo provides the full enforcement stack that makes Claude **actually use** these tools instead of falling back to `Read`:

| Layer | What | Effect |
|-------|------|--------|
| CLAUDE.md rules | Instructions | Tells Claude *when* to use jCodeMunch/jDocMunch |
| PreToolUse nudge hooks | Non-blocking | Reminds Claude when it tries `Read` on code/doc files |
| Session gate | Blocking | Blocks ALL tools until indexes are refreshed at session start |
| Agent spawn gate | Blocking | Blocks subagent spawning without MCP instructions in prompt |
| PostToolUse trackers | Passive | Tracks genuine token savings, triggers re-index after edits/commits |
| Statusline | Display | Shows JCM/JDM savings counters in the Claude Code status bar |

## Quick Start

```bash
# 1. Install the MCP servers
uv tool install jcodemunch-mcp
uv tool install jdocmunch-mcp

# 2. Add MCP config to your project
cp rules/mcp-example.json .mcp.json

# 3. Copy hooks to your project
mkdir -p .claude/hooks
cp hooks/project/*.sh .claude/hooks/
cp hooks/global/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh

# 4. Add settings (merge with your existing .claude/settings.json)
# See rules/project-settings-example.json

# 5. Add CLAUDE.md rules (append to ~/.claude/CLAUDE.md)
# See rules/global-claude-md.md

# 6. Allow MCP tools (add to .claude/settings.local.json)
# See rules/allowed-tools.txt
```

See [docs/setup-guide.md](docs/setup-guide.md) for the full step-by-step walkthrough.

## Repository Structure

```
hooks/
  global/                          # Install to ~/.claude/hooks/ (all projects)
    jcodemunch-nudge.sh            # PreToolUse:Read — blocks Read on .py/.ts/.tsx
    jdocmunch-nudge.sh             # PreToolUse:Read — blocks Read on large .md files
    reindex-after-edit.sh          # PostToolUse:Write|Edit — triggers re-index
  project/                         # Install to .claude/hooks/ (per project)
    agent-jcodemunch-gate.sh       # PreToolUse:Agent — blocks agents without MCP instructions
    jmunch-session-start.sh        # SessionStart — injects index refresh prompt
    jmunch-session-gate.sh         # PreToolUse:* — blocks all tools until indexes ready
    jmunch-sentinel-writer.sh      # PostToolUse — marks indexes as refreshed
    reindex-after-commit.sh        # PostToolUse:Bash — re-index after git commits
    track-genuine-savings.sh       # PostToolUse — tracks genuine token savings
rules/
  global-claude-md.md              # CLAUDE.md rules for ~/.claude/CLAUDE.md
  project-settings-example.json    # Example .claude/settings.json with all hooks
  mcp-example.json                 # Example .mcp.json for project root
  allowed-tools.txt                # MCP tool allowlist for settings.local.json
statusline/
  statusline-command.sh            # VBW wrapper with JCM/JDM counters (3 decimal places)
  statusline-standalone.sh         # Standalone version (no VBW dependency)
docs/
  setup-guide.md                   # Full step-by-step setup guide
```

## How Enforcement Works

### Session Lifecycle

```
Session starts
  -> jmunch-session-start.sh injects "run indexes NOW" prompt
  -> jmunch-session-gate.sh blocks ALL tools until indexes done
  -> Claude runs index_folder + index_local
  -> jmunch-sentinel-writer.sh marks session as ready
  -> All tools unblocked

Claude needs a function
  -> Tries Read on .py file
  -> jcodemunch-nudge.sh fires: BLOCKED, use get_symbol
  -> Claude uses get_symbol instead
  -> track-genuine-savings.sh logs tokens_saved

Claude spawns a subagent
  -> agent-jcodemunch-gate.sh checks prompt for MCP instructions
  -> Missing? BLOCKED with full copy-paste instructions
  -> Present? Allowed

Claude edits a file
  -> reindex-after-edit.sh fires (debounced 30s)
  -> Prompts Claude to re-run index_folder/index_local

Claude commits
  -> reindex-after-commit.sh clears sentinel
  -> All tools blocked until re-index
```

### Genuine Token Savings (`_genuine_savings.json`)

Both MCP servers report a `tokens_saved` field in every response's `_meta`. However, not all reported savings reflect actual token reduction — tools like `get_file_outline` return a small summary and report savings as if you would have read the entire file, when in practice you wouldn't have. These optimistic counts can make the totals appear 3-5x higher than reality.

The `track-genuine-savings.sh` hook addresses this by filtering. It only counts savings from tools that **actually replace a `Read`** — i.e., tools where Claude would have had to read the full file if the MCP server weren't available.

| Directly replaces Read (counted) | Optimistic (skipped) |
|---|---|
| `get_symbol` | `get_file_outline` |
| `get_symbols` | `get_repo_outline` |
| `search_symbols` | `get_file_tree` |
| `search_text` | `index_folder` |
| `get_file_content` (with line ranges) | `index_repo` |
| `get_section` | `index_local` |
| `get_sections` | `list_repos` |
| `search_sections` | `invalidate_cache` |

> **Special case:** `get_file_content` is only counted as genuine when called with `start_line` or `end_line` parameters (a sliced read). Without line ranges it returns the full file — same as `Read`, no savings.

#### Where the file lives

```
~/.code-index/_genuine_savings.json
```

This file is created automatically on the first genuine MCP tool call. It accumulates across sessions.

#### What it looks like

```json
{
  "total_genuine_tokens_saved": 920376,
  "by_tool": {
    "mcp__jcodemunch__get_symbol": 260902,
    "mcp__jcodemunch__search_symbols": 243247,
    "mcp__jcodemunch__get_file_content": 414119,
    "mcp__jdocmunch__search_sections": 2108
  },
  "call_counts": {
    "mcp__jcodemunch__get_symbol": 23,
    "mcp__jcodemunch__search_symbols": 12,
    "mcp__jcodemunch__get_file_content": 8,
    "mcp__jdocmunch__search_sections": 1
  }
}
```

#### How it flows into the statusline

The statusline scripts read `_genuine_savings.json` and split the `by_tool` totals by prefix:
- `mcp__jcodemunch__*` entries sum to **JCM** (jCodeMunch savings)
- `mcp__jdocmunch__*` entries sum to **JDM** (jDocMunch savings)

These are formatted with K/M suffixes and displayed as `JCM:920.376K JDM:2.108K`.

> **Note:** The MCP servers also write their own `_savings.json` files (`~/.code-index/_savings.json` and `~/.doc-index/_savings.json`) with `total_tokens_saved` — but those include optimistic counts from all tools. The statusline deliberately reads the genuine file, not those.

## Statusline

Two versions provided:

- **`statusline-command.sh`** — Wraps VBW statusline, appends JCM/JDM counters to Line 4
- **`statusline-standalone.sh`** — Independent statusline with context bar + JCM/JDM counters

Both display token savings with 3 decimal places (e.g., `JCM:199.581K JDM:2.108K`).

Register in `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline-command.sh\""
  }
}
```

## Subagent Instructions Template

When spawning subagents, include these instructions in the prompt to ensure they use jCodeMunch/jDocMunch:

```
**Code navigation (MANDATORY):** Use jCodeMunch MCP tools for all Python/TypeScript code exploration.
- Use mcp__jcodemunch__get_symbol to fetch specific functions/classes — NEVER read an entire .py/.ts/.tsx file to find one function
- Use mcp__jcodemunch__search_symbols instead of Grep for function/class definitions
- **Sliced edit workflow:** get_symbol (find line range) -> get_file_content(start_line=line-4, end_line=end_line+3) -> Edit
- Full Read only when: editing 6+ functions in same file, need imports/globals, file <50 lines, non-code files

**Doc navigation (MANDATORY):** Use jDocMunch MCP tools for documentation files.
- Use mcp__jdocmunch__search_sections to find relevant doc sections
- Use mcp__jdocmunch__get_section for specific content by section ID
- Fall back to Read ONLY for small docs (<50 lines) or planning files
```

The `agent-jcodemunch-gate.sh` hook enforces this — spawning is blocked if these instructions are missing.

## Requirements

- [Claude Code](https://claude.ai/claude-code) CLI
- [uv](https://docs.astral.sh/uv/) for package management
- `jq` for JSON parsing in hooks
- `python3` for hook input parsing
- `bc` for statusline number formatting

## Credits

- [jCodeMunch MCP](https://github.com/jgravelle/jcodemunch-mcp) by jgravelle
- [jDocMunch MCP](https://github.com/jgravelle/jdocmunch-mcp) by jgravelle

## License

The hooks, rules, statusline scripts, and documentation in this repository are licensed under the [MIT License](LICENSE).

This repo does **not** include the jCodeMunch or jDocMunch MCP servers themselves — only configuration and enforcement tooling that works with them. The MCP servers are separate projects by [jgravelle](https://github.com/jgravelle) and are subject to their own licenses. See [jcodemunch-mcp](https://github.com/jgravelle/jcodemunch-mcp) and [jdocmunch-mcp](https://github.com/jgravelle/jdocmunch-mcp) for their respective terms.
