# jCodeMunch + jDocMunch Setup for Claude Code

Hooks, rules, and statusline integration for [jCodeMunch](https://github.com/jgravelle/jcodemunch-mcp) and [jDocMunch](https://github.com/jgravelle/jdocmunch-mcp) — two excellent MCP servers created by [J. Gravelle (jgravelle)](https://github.com/jgravelle) that dramatically reduce token usage in Claude Code. Optional [context-mode](https://github.com/mksglu/context-mode) integration for large data files and command outputs. Optional [MuninnDB Lite](https://github.com/Aperrix/muninndb-lite) integration for persistent cross-session memory, created by [MJ Bonanno](https://scrypster.com).

> **Credit where it's due:**
> - [jCodeMunch](https://github.com/jgravelle/jcodemunch-mcp) and [jDocMunch](https://github.com/jgravelle/jdocmunch-mcp) are built and maintained by [J. Gravelle](https://github.com/jgravelle). All the clever indexing and symbol extraction is jgravelle's work.
> - [context-mode](https://github.com/mksglu/context-mode) is built and maintained by [mksglu](https://github.com/mksglu). The sandboxed execution, FTS5 indexing, and session persistence are mksglu's work.
> - [MuninnDB Lite](https://github.com/Aperrix/muninndb-lite) is built and maintained by [MJ Bonanno (Aperrix)](https://scrypster.com) ([GitHub](https://github.com/Aperrix)). The cognitive memory engine, Ebbinghaus decay, Hebbian learning, and entity graph are MJ Bonanno's work.
>
> This repo does not contain any of those MCP servers — it provides a companion enforcement and tracking layer that helps Claude Code get the most out of them.

## What It Covers

| Layer | MCP server | What it does | Token savings |
|-------|-----------|--------------|---------------|
| Code (.py/.ts/.tsx) | **jCodeMunch** (by jgravelle) | Fetches individual functions via AST parsing | ~85-95% |
| Docs (.md/.mdx/.rst) | **jDocMunch** (by jgravelle) | Fetches specific sections by heading | ~90-95% |
| Data (.json/.html, large) | **context-mode** (by mksglu) | Sandboxes file reads, only filtered analysis enters context | ~90-98% |
| Command outputs | **context-mode** (by mksglu) | Sandboxes test/build/search output | ~90-98% |
| Cross-session memory | **MuninnDB Lite** (by Aperrix) | Persists knowledge across sessions with cognitive decay and entity graphs | N/A (memory, not navigation) |

jCodeMunch + jDocMunch are **always included**. context-mode and MuninnDB Lite are **optional** — enable them per-project with flags.

This repo provides the enforcement stack that makes Claude **actually use** these tools instead of falling back to `Read` and `Bash`:

| Layer | What | Effect |
|-------|------|--------|
| CLAUDE.md rules | Instructions | Tells Claude *when* to use each MCP tool |
| PreToolUse nudge hooks | Blocking | Redirects Read/Bash to the right MCP tool |
| Session gate | Blocking | Blocks ALL tools until indexes are refreshed at session start |
| Agent spawn gate | Blocking | Blocks subagent spawning without MCP instructions in prompt |
| PostToolUse trackers | Passive | Tracks genuine token savings, triggers re-index after edits/commits |
| Statusline | Display | Shows JCM/JDM/CTX savings counters in the Claude Code status bar |

## Quick Start

### Install (one command)

```bash
# Install the MCP servers first
uv tool install jcodemunch-mcp
uv tool install jdocmunch-mcp

# Optional: install MuninnDB Lite for cross-session memory
curl -fsSL https://raw.githubusercontent.com/Aperrix/muninndb-lite/develop/install.sh | sh

# Recommended: register MuninnDB globally (data lives at ~/.muninn/data regardless)
# If ~/.claude/.mcp.json exists, merge the muninn entry from rules/global-mcp-muninn.json into it.
# If it doesn't exist yet:
cp rules/global-mcp-muninn.json ~/.claude/.mcp.json

# Then install the hooks
curl -sSL https://raw.githubusercontent.com/shacharbard/jmunch-claude-code-setup/stable/install.sh | bash
```

This clones the repo to `~/.jmunch-hooks`, symlinks all hooks globally, verifies checksums, and registers auto-updates. No manual configuration needed.

### Set up a project

For each project where you want enforcement:

```bash
cd /path/to/your/project

# jCodeMunch + jDocMunch only (default)
bash ~/.jmunch-hooks/scripts/init-project.sh

# jCodeMunch + jDocMunch + context-mode
bash ~/.jmunch-hooks/scripts/init-project.sh --context-mode

# Full stack: code + docs + data + memory
bash ~/.jmunch-hooks/scripts/init-project.sh --context-mode --muninn
```

Or do both install + project setup in one step:

```bash
curl -sSL https://raw.githubusercontent.com/shacharbard/jmunch-claude-code-setup/stable/install.sh | bash -s -- --project /path/to/your/project
```

This creates everything the project needs:
- `.claude/hooks/` — symlinks to the global hooks (always up to date)
- `.claude/settings.json` — hook registrations (session gate, nudges, agent gate, savings tracking)
- `.claude/settings.local.json` — MCP tool permissions (no approval prompts)
- `.mcp.json` — MCP server config (jcodemunch + jdocmunch, optionally context-mode and muninn)

Safe to re-run — skips existing files, backs up before overwriting.

### context-mode: do I need it?

| If you... | Use |
|-----------|-----|
| Work with Python/TypeScript code and markdown docs | Default (`init-project.sh`) — jCodeMunch + jDocMunch is all you need |
| Also work with large JSON files, HTML, or run test suites with long output | `init-project.sh --context-mode` — adds data file + command output sandboxing |
| Already have context-mode installed via npm | `--context-mode` just registers the hooks and MCP config — it doesn't install context-mode itself. The `.mcp.json` uses `npx -y context-mode` which auto-downloads on first use. |
| Don't use context-mode and don't want it | Do nothing. The default setup doesn't touch context-mode. Even if the hooks are symlinked globally, they check your project's `.mcp.json` before doing anything — no context-mode in `.mcp.json` = no enforcement, zero impact. |
| Want to add context-mode to a project later | Re-run `init-project.sh --context-mode` — it adds what's missing without overwriting existing config. |

### MuninnDB Lite: do I need it?

| If you... | Use |
|-----------|-----|
| Want Claude to remember facts, decisions, and patterns across sessions | **Global install recommended** — copy `rules/global-mcp-muninn.json` to `~/.claude/.mcp.json` (or merge the muninn entry if the file exists). This makes MuninnDB available in every project automatically. |
| Work across multiple projects and want shared knowledge | Global install — MuninnDB data lives at `~/.muninn/data` regardless of config location, so global is the natural fit |
| Want per-project control over whether MuninnDB starts | `init-project.sh --muninn` — adds a per-project `.mcp.json` entry. Only needed if you want MuninnDB in some projects but not others. |
| Only need code/doc navigation within a single session | Do nothing. MuninnDB is opt-in. |
| Already use Claude Code's built-in file-based memory | Both can co-exist. File-based memory stays human-readable and project-scoped. MuninnDB adds semantic search, cognitive decay, and entity graphs. |

MuninnDB Lite is a single Go binary (~16 MB) with no runtime dependencies. Data is stored at `~/.muninn/data` — this is always the same location regardless of whether MuninnDB is configured globally or per-project. The config only controls whether the MCP server starts, not where data lives. Works without API keys (BM25 search); optional embedding providers (Ollama, OpenAI, etc.) add semantic vector search.

> **Note:** MuninnDB Lite is alpha software (v0.4.2-alpha-lite) under BSL 1.1 license (free for individuals, converts to Apache 2.0 in 2030).

### Add CLAUDE.md rules

Append the rules to your global `~/.claude/CLAUDE.md` — see [rules/global-claude-md.md](rules/global-claude-md.md).

See [docs/setup-guide.md](docs/setup-guide.md) for the full step-by-step walkthrough.

## Security

These hooks run as shell scripts with your user permissions every time Claude Code starts a session or calls a tool. We take that seriously. Here's what we do to keep you safe:

| Measure | What it does | Why it matters |
|---------|-------------|----------------|
| **Stable branch** | Users track the `stable` branch, which is only updated on explicit releases | You never get untested work-in-progress code. Only reviewed, tagged releases reach `stable`. |
| **Fast-forward only** | Auto-updates use `git pull --ff-only` | Rejects force-pushes and history rewrites. An attacker cannot rewrite past commits to inject malicious code. |
| **Remote URL verification** | Both `sync-hooks.sh` and `auto-update-hooks.sh` verify the git remote matches `shacharbard/jmunch-claude-code-setup` | Prevents a hijacked or swapped remote from serving malicious code. If the remote doesn't match, the update is blocked and logged. |
| **SHA256 checksums** | Every release includes `CHECKSUMS.sha256` with hashes of all distributed scripts | Run `sync-hooks.sh --verify` at any time to confirm no file has been tampered with since the release. |
| **Update logging** | Every auto-update logs the old/new commit hash and changed files to `~/.claude/jmunch-update.log` | Full audit trail. You can see exactly what changed and when. |
| **Tagged releases** | Releases are tagged with semantic versions (e.g., `v1.0.0`) | You can pin to a specific version and upgrade on your own schedule. |
| **Plain bash scripts** | All hooks are standard bash — no compiled binaries, no obfuscated code, no network calls (except `git pull`) | You can read every line of code that runs on your machine. Nothing is hidden. |
| **No secrets or data collection** | Hooks only process Claude Code tool metadata (tool names, file paths). No data leaves your machine. | Savings tracking writes to local JSON files only. Nothing is phoned home. |
| **Symlinks, not copies** | `sync-hooks.sh` creates symlinks to the repo, not copies | You always know exactly which code is running — it's the files in the repo. No hidden divergence between "installed" and "source" versions. |
| **Configurable repo path** | Set `JMUNCH_REPO_DIR` env var to override the default repo location | Works with any clone location. The auto-updater doesn't assume where you put the repo. |
| **Configurable branch** | Set `JMUNCH_BRANCH` env var to track a different branch | Advanced users can track `main` for bleeding-edge, or pin to a specific tag for maximum stability. |

### Verifying integrity

After installation or at any time:

```bash
bash ~/Development/AI/jmunch-claude-code-setup/scripts/sync-hooks.sh --verify
```

This checks every file against the published SHA256 checksums. If any file has been modified — whether by an attacker, a bad merge, or an accidental edit — you'll see:

```
  ✓ hooks/global/jcodemunch-nudge.sh
  ✓ hooks/global/jdocmunch-nudge.sh
  ✗ hooks/project/jmunch-session-gate.sh (CHECKSUM MISMATCH)
      Expected: c9eef572...
      Actual:   a1b2c3d4...
```

### Reviewing the update log

```bash
cat ~/.claude/jmunch-update.log
```

```
[2026-03-17T14:30:00Z] Updated: 59eb2a8 -> 7642ab2
  hooks/global/auto-update-hooks.sh
  scripts/sync-hooks.sh
```

### What we recommend

- **Track `stable`** (the default) for production use
- **Run `--verify`** after first install and periodically
- **Read the hooks** — they're short bash scripts, each under 60 lines
- **Check the log** if something feels off: `~/.claude/jmunch-update.log`

## Repository Structure

```
hooks/
  global/                          # Install to ~/.claude/hooks/ (all projects)
    auto-update-hooks.sh           # SessionStart — auto-pulls latest from GitHub
    jcodemunch-nudge.sh            # PreToolUse:Read — blocks Read on .py/.ts/.tsx
    jdocmunch-nudge.sh             # PreToolUse:Read — blocks Read on large .md files
    context-mode-nudge.sh          # PreToolUse:Read — blocks Read on large .json/.html (opt-in)
    context-mode-bash-nudge.sh     # PreToolUse:Bash — blocks large-output commands (opt-in)
    reindex-after-edit.sh          # PostToolUse:Write|Edit — triggers re-index
  project/                         # Install to .claude/hooks/ (per project)
    agent-jcodemunch-gate.sh       # PreToolUse:Agent — blocks agents without MCP instructions
    jmunch-session-start.sh        # SessionStart — injects index refresh prompt
    jmunch-session-gate.sh         # PreToolUse:* — blocks all tools until indexes ready
    jmunch-sentinel-writer.sh      # PostToolUse — marks indexes as refreshed
    reindex-after-commit.sh        # PostToolUse:Bash — re-index after git commits
    track-genuine-savings.sh       # PostToolUse — tracks jCodeMunch/jDocMunch token savings
    track-genuine-savings-ctx.sh   # PostToolUse — tracks context-mode token savings (opt-in)
scripts/
  init-project.sh                  # Set up jmunch enforcement in a new project (one command)
  sync-hooks.sh                    # Symlink all hooks to ~/.claude/hooks/ (with --verify)
  release.command                  # Double-click to tag + release to stable branch
  generate-checksums.sh            # Regenerate CHECKSUMS.sha256 for a release
rules/
  global-claude-md.md              # CLAUDE.md rules for ~/.claude/CLAUDE.md
  global-mcp-muninn.json           # MuninnDB global config for ~/.claude/.mcp.json
  project-settings-example.json    # Example .claude/settings.json with all hooks
  mcp-example.json                 # Example .mcp.json for project root (all servers)
  allowed-tools.txt                # MCP tool allowlist for settings.local.json
statusline/
  statusline-command.sh            # VBW wrapper with JCM/JDM counters (3 decimal places)
  statusline-standalone.sh         # Standalone version (no VBW dependency)
docs/
  setup-guide.md                   # Full step-by-step setup guide
CHECKSUMS.sha256                   # SHA256 hashes for all distributed scripts
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

Claude needs a large JSON file (context-mode enabled)
  -> Tries Read on data.json (500 lines)
  -> context-mode-nudge.sh fires: BLOCKED, use ctx_execute_file
  -> Claude uses ctx_execute_file instead
  -> track-genuine-savings-ctx.sh logs tokens_saved

Claude runs a test suite (context-mode enabled)
  -> Tries Bash("pytest tests/")
  -> context-mode-bash-nudge.sh fires: BLOCKED, use ctx_execute
  -> Claude uses ctx_execute(language="shell", ...) instead
  -> track-genuine-savings-ctx.sh logs tokens_saved

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
```

### Genuine Token Savings (`_genuine_savings.json`)

Both MCP servers report a `tokens_saved` field in every response's `_meta` — a helpful feature built into jCodeMunch and jDocMunch by jgravelle. The reported numbers represent the *theoretical maximum* savings (the full file size minus the returned content), which is a perfectly reasonable way to measure it. In practice, though, some tools like `get_file_outline` serve a different purpose than replacing a full `Read`, so counting their savings alongside direct replacements can paint an optimistic picture of actual token reduction.

> **Note:** This distinction is purely about how *we* choose to measure savings for our statusline — it is not a criticism of the MCP servers or their reporting. The `tokens_saved` field works exactly as designed.

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

If context-mode is enabled, `_genuine_savings_ctx.json` adds a third counter:
- `mcp__context-mode__*` entries sum to **CTX** (context-mode savings)

These are formatted with K/M suffixes and displayed as `JCM:920.376K JDM:2.108K CTX:58.375K`.

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

If context-mode is enabled, add this block after the above:

```
**Command & data navigation (MANDATORY):** Use context-mode MCP tools for large outputs.
- Test/build/search commands: mcp__context-mode__ctx_execute(language="shell", code="...") instead of Bash
- Large JSON (>100 lines): mcp__context-mode__ctx_execute_file instead of Read
- Large HTML: mcp__context-mode__ctx_execute_file instead of Read
- ctx_execute_file provides file content as FILE_CONTENT variable — do NOT use open() or sys.argv
- Bash only for: git status/add/commit/push, ls/mkdir/mv, package installs, file redirects
```

If MuninnDB is enabled, add this block after the above:

```
**Cross-session memory:** Use MuninnDB MCP tools for persistent knowledge.
- mcp__muninn__muninn_recall to retrieve relevant memories before starting work
- mcp__muninn__muninn_remember to store important discoveries, decisions, or patterns
- mcp__muninn__muninn_where_left_off to resume context from previous sessions
- Do NOT store raw data — store the distilled insight instead
```

The `agent-jcodemunch-gate.sh` hook enforces jCodeMunch/jDocMunch instructions — spawning is blocked if these are missing.

## Requirements

- [Claude Code](https://claude.ai/claude-code) CLI
- [uv](https://docs.astral.sh/uv/) for package management
- `jq` for JSON parsing in hooks
- `python3` for hook input parsing
- `bc` for statusline number formatting
- `curl` for MuninnDB Lite installation (optional)

## Credits

- [jCodeMunch MCP](https://github.com/jgravelle/jcodemunch-mcp) by [jgravelle](https://github.com/jgravelle)
- [jDocMunch MCP](https://github.com/jgravelle/jdocmunch-mcp) by [jgravelle](https://github.com/jgravelle)
- [context-mode](https://github.com/mksglu/context-mode) by [mksglu](https://github.com/mksglu)
- [MuninnDB Lite](https://github.com/Aperrix/muninndb-lite) by [MJ Bonanno (Aperrix)](https://scrypster.com)

## License

The hooks, rules, statusline scripts, and documentation in this repository are licensed under the [MIT License](LICENSE).

This repo does **not** include jCodeMunch, jDocMunch, context-mode, or MuninnDB Lite — only configuration and enforcement tooling that works with them. The MCP servers are separate projects by their respective authors and are subject to their own licenses:
- jCodeMunch/jDocMunch: see [jcodemunch-mcp](https://github.com/jgravelle/jcodemunch-mcp) and [jdocmunch-mcp](https://github.com/jgravelle/jdocmunch-mcp)
- context-mode: [ELv2 (Elastic License v2)](https://github.com/mksglu/context-mode/blob/main/LICENSE)
- MuninnDB Lite: [BSL 1.1](https://github.com/Aperrix/muninndb-lite/blob/develop/LICENSE) (free for individuals, converts to Apache 2.0 in 2030)
