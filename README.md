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

# 2. Clone this repo
git clone https://github.com/shacharbard/jmunch-claude-code-setup.git ~/Development/AI/jmunch-claude-code-setup
cd ~/Development/AI/jmunch-claude-code-setup

# 3. Switch to the stable branch (recommended for production use)
git checkout stable

# 4. Run the sync script — symlinks all hooks, no copying needed
bash scripts/sync-hooks.sh --verify

# 5. Add MCP config to your project
cp rules/mcp-example.json /path/to/your/project/.mcp.json

# 6. Add settings (merge with your existing .claude/settings.json)
# See rules/project-settings-example.json

# 7. Add CLAUDE.md rules (append to ~/.claude/CLAUDE.md)
# See rules/global-claude-md.md

# 8. Allow MCP tools (add to .claude/settings.local.json)
# See rules/allowed-tools.txt
```

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
    reindex-after-edit.sh          # PostToolUse:Write|Edit — triggers re-index
  project/                         # Install to .claude/hooks/ (per project)
    agent-jcodemunch-gate.sh       # PreToolUse:Agent — blocks agents without MCP instructions
    jmunch-session-start.sh        # SessionStart — injects index refresh prompt
    jmunch-session-gate.sh         # PreToolUse:* — blocks all tools until indexes ready
    jmunch-sentinel-writer.sh      # PostToolUse — marks indexes as refreshed
    reindex-after-commit.sh        # PostToolUse:Bash — re-index after git commits
    track-genuine-savings.sh       # PostToolUse — tracks genuine token savings
scripts/
  sync-hooks.sh                    # Symlink all hooks to ~/.claude/hooks/ (with --verify)
  release.command                  # Double-click to tag + release to stable branch
  update-mcp-servers.command       # Double-click to update MCP server packages
  generate-checksums.sh            # Regenerate CHECKSUMS.sha256 for a release
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
