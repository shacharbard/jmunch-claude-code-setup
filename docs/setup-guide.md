# Setting Up jCodeMunch & jDocMunch in a Claude Code Project

A step-by-step guide to install, configure, and enforce jCodeMunch (code navigation) and jDocMunch (doc navigation) MCP servers in any Claude Code project — including hooks, rules, and statusline token savings counters.

## What These Tools Do

- **jCodeMunch** — indexes your code (Python, TypeScript, etc.) and lets Claude fetch individual functions/classes instead of reading entire files. Saves ~85-95% of tokens on code exploration.
- **jDocMunch** — indexes your documentation (.md, .mdx, .rst) and lets Claude fetch specific sections instead of reading entire docs. Saves ~90-95% on doc lookups.

Both tools report `tokens_saved` in every response, which we track and display in the statusline.

---

## Step 1: Install the MCP Servers

Both tools are Python packages. Install them globally with `uv`:

```bash
uv tool install jcodemunch-mcp
uv tool install jdocmunch-mcp
```

Verify they work:
```bash
jcodemunch-mcp --help
jdocmunch-mcp --help
```

> **Why `uv tool`?** It installs each package in its own isolated virtualenv and adds the command to your PATH. No conflicts with other Python packages.

---

## Step 2: Register as MCP Servers

### Option A: Project-level `.mcp.json` (recommended)

Create `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "jcodemunch": {
      "command": "jcodemunch-mcp",
      "args": [],
      "type": "stdio"
    },
    "jdocmunch": {
      "command": "jdocmunch-mcp",
      "args": [],
      "type": "stdio"
    }
  }
}
```

> This makes the tools available whenever Claude Code opens this project.

### Option B: Global registration (all projects)

```bash
claude mcp add jcodemunch -- jcodemunch-mcp
claude mcp add jdocmunch -- jdocmunch-mcp
```

Or add manually to `~/.claude/settings.json` under `mcpServers`.

---

## Step 3: Allow the MCP Tools

Claude Code needs permission to use each MCP tool. Add these to your project's `.claude/settings.local.json` under `allowedTools`:

```
mcp__jcodemunch__get_symbol
mcp__jcodemunch__get_symbols
mcp__jcodemunch__search_symbols
mcp__jcodemunch__search_text
mcp__jcodemunch__get_file_content
mcp__jcodemunch__get_file_outline
mcp__jcodemunch__get_file_tree
mcp__jcodemunch__get_repo_outline
mcp__jcodemunch__index_folder
mcp__jcodemunch__index_repo
mcp__jcodemunch__invalidate_cache
mcp__jcodemunch__list_repos
mcp__jcodemunch__find_importers
mcp__jcodemunch__find_references
mcp__jdocmunch__index_local
mcp__jdocmunch__index_repo
mcp__jdocmunch__list_repos
mcp__jdocmunch__get_toc
mcp__jdocmunch__get_toc_tree
mcp__jdocmunch__get_document_outline
mcp__jdocmunch__search_sections
mcp__jdocmunch__get_section
mcp__jdocmunch__get_sections
mcp__jdocmunch__delete_index
```

> Without these, Claude will ask for permission on every single tool call.

---

## Step 4: Install Hooks

Copy the hook scripts to your project:

```bash
mkdir -p .claude/hooks

# Global hooks (can also go in ~/.claude/hooks/)
cp hooks/global/jcodemunch-nudge.sh .claude/hooks/
cp hooks/global/jdocmunch-nudge.sh .claude/hooks/
cp hooks/global/reindex-after-edit.sh .claude/hooks/

# Project hooks
cp hooks/project/agent-jcodemunch-gate.sh .claude/hooks/
cp hooks/project/jmunch-session-start.sh .claude/hooks/
cp hooks/project/jmunch-session-gate.sh .claude/hooks/
cp hooks/project/jmunch-sentinel-writer.sh .claude/hooks/
cp hooks/project/reindex-after-commit.sh .claude/hooks/
cp hooks/project/track-genuine-savings.sh .claude/hooks/

# Make executable
chmod +x .claude/hooks/*.sh
```

### What Each Hook Does

| Hook | Event | Effect |
|------|-------|--------|
| `jmunch-session-start.sh` | SessionStart | Injects "run indexes NOW" prompt at session start |
| `jmunch-session-gate.sh` | PreToolUse:* | **Blocks ALL tools** until indexes are refreshed |
| `jmunch-sentinel-writer.sh` | PostToolUse:index_* | Marks indexes as ready, unblocks tools |
| `jcodemunch-nudge.sh` | PreToolUse:Read | **Blocks** Read on .py/.ts/.tsx files |
| `jdocmunch-nudge.sh` | PreToolUse:Read | **Blocks** Read on large .md/.mdx/.rst files |
| `agent-jcodemunch-gate.sh` | PreToolUse:Agent | **Blocks** agent spawn without MCP instructions |
| `reindex-after-edit.sh` | PostToolUse:Write\|Edit | Prompts re-index after code/doc changes (30s debounce) |
| `reindex-after-commit.sh` | PostToolUse:Bash | Soft nudge to re-index after git commits (subagent-safe) |
| `track-genuine-savings.sh` | PostToolUse:mcp__j*__ | Tracks genuine token savings to JSON |

---

## Step 5: Register Hooks in Settings

Merge the hook configuration into your project's `.claude/settings.json`. See `rules/project-settings-example.json` for the full example.

The key sections:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/jmunch-session-start.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/jmunch-session-gate.sh" }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/jcodemunch-nudge.sh" },
          { "type": "command", "command": "bash .claude/hooks/jdocmunch-nudge.sh" }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/agent-jcodemunch-gate.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__jcodemunch__index_folder",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/jmunch-sentinel-writer.sh" }
        ]
      },
      {
        "matcher": "mcp__jdocmunch__index_local",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/jmunch-sentinel-writer.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/reindex-after-commit.sh" }
        ]
      },
      {
        "matcher": "mcp__jcodemunch__*",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/track-genuine-savings.sh" }
        ]
      },
      {
        "matcher": "mcp__jdocmunch__*",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/track-genuine-savings.sh" }
        ]
      }
    ]
  }
}
```

---

## Step 6: Add CLAUDE.md Rules

The hooks make the tools *enforced*. The CLAUDE.md rules tell Claude *when* to prefer them over `Read`.

Append the contents of `rules/global-claude-md.md` to your `~/.claude/CLAUDE.md`.

> **Why this matters:** Without these rules, Claude defaults to `Read` for everything. The rules make jCodeMunch/jDocMunch the default, with `Read` as the exception. The sliced edit workflow is the biggest savings lever — it prevents reading a 500-line file just to edit one function.

---

## Step 7: Track Token Savings

The `track-genuine-savings.sh` hook writes to `~/.code-index/_genuine_savings.json`:

```json
{
  "total_genuine_tokens_saved": 920376,
  "by_tool": {
    "mcp__jcodemunch__get_symbol": 260902,
    "mcp__jdocmunch__search_sections": 2108,
    "mcp__jcodemunch__search_symbols": 243247,
    "mcp__jcodemunch__get_file_content": 414119
  },
  "call_counts": {
    "mcp__jcodemunch__get_symbol": 23,
    "mcp__jdocmunch__search_sections": 1,
    "mcp__jcodemunch__search_symbols": 12,
    "mcp__jcodemunch__get_file_content": 8
  }
}
```

### Genuine vs Optimistic

Only tools that actually replace a `Read` are counted:

| Directly replaces Read (counted) | Optimistic (skipped) |
|---|---|
| `get_symbol`, `get_symbols` | `get_file_outline`, `get_repo_outline` |
| `search_symbols`, `search_text` | `get_file_tree` |
| `get_file_content` (with line ranges) | `index_folder`, `index_repo` |
| `get_section`, `get_sections`, `search_sections` | `index_local`, `list_repos` |

---

## Step 8: Statusline with JCM/JDM Counters

Two versions are provided in `statusline/`:

### VBW Wrapper (`statusline-command.sh`)

Wraps the VBW plugin's statusline and appends JCM/JDM savings to Line 4:

```
... VBW output ... | JCM:199.581K (today:45.200K) JDM:2.108K
```

### Standalone (`statusline-standalone.sh`)

Independent statusline with context bar + JCM/JDM counters:

```
leaflet  ████░░░░░░ 40%  JCM:920.376K JDM:2.108K  14:32
```

Both use 3 decimal places for precision.

### Installation

```bash
cp statusline/statusline-command.sh ~/.claude/statusline-command.sh
# or for standalone:
# cp statusline/statusline-standalone.sh ~/.claude/statusline-command.sh

chmod +x ~/.claude/statusline-command.sh
```

Register in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline-command.sh\""
  }
}
```

---

## Data Flow Summary

```
Session starts
  -> jmunch-session-start.sh injects "run indexes" prompt
  -> jmunch-session-gate.sh blocks ALL tools
  -> Claude runs index_folder + index_local
  -> jmunch-sentinel-writer.sh marks both as ready
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
  -> reindex-after-commit.sh nudges Claude to re-index
  -> Soft nudge (no sentinel deletion) — safe for subagents

Statusline renders
  -> Reads _genuine_savings.json
  -> Splits by mcp__jcodemunch__ vs mcp__jdocmunch__ prefix
  -> Displays: JCM:920.376K JDM:2.108K
```

---

## Troubleshooting

**"jcodemunch-mcp: command not found"**
-> Run `uv tool install jcodemunch-mcp` and ensure `~/.local/bin` is in your PATH.

**Statusline shows JCM:0**
-> The `track-genuine-savings.sh` hook only fires on jCodeMunch tool calls. Use `get_symbol` at least once to see savings.

**Agent spawn blocked**
-> Include the jCodeMunch/jDocMunch instructions in your agent prompt. The gate checks for keywords like `jcodemunch`, `get_symbol`, `search_sections`.

**Index is stale after edits**
-> The `reindex-after-edit.sh` hook debounces at 30 seconds. If you made rapid edits, run `index_folder` manually.

**`_genuine_savings.json` doesn't exist**
-> It's created on the first genuine tool call. Use jCodeMunch at least once.

**All tools blocked at session start**
-> This is intentional. The session gate blocks everything until both indexes are refreshed. Just let Claude run `index_folder` and `index_local` first.
