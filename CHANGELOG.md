# Changelog

All notable changes to this project are documented here.
Updated automatically on each release.

## v1.0.7

- fix(hooks): expand file type coverage and remove redundant commit hook


## v1.0.6

- fix(muninn): use claude mcp add --scope user instead of ~/.claude/.mcp.json
- feat(muninn): recommend global MuninnDB installation over per-project


## v1.0.5

- docs(readme): credit MJ Bonanno by name for MuninnDB Lite


## v1.0.4

- fix(savings): separate JCM and JDM genuine savings into their own directories
- feat(muninn): add MuninnDB Lite as optional cross-session memory layer


## v1.0.3

- chore(release): regenerate checksums after routing fallback fix
- fix(routing): respect smart routing decision in no-context-mode fallback
- chore(release): regenerate checksums after v1.4 routing update
- fix(routing): update jDocMunch/context-mode routing for v1.4 file types


## v1.0.2

- chore(release): update checksums after sentinel hash fix
- fix(hooks): stabilize sentinel hash for worktrees, submodules, and non-root sessions


## v1.0.1

- fix(release): find repo correctly when run from Desktop
- fix(changelog): remove hardcoded version header
- docs(changelog): rename version to v1.0.1
- docs(claude): add CHANGELOG rule and track CLAUDE.md in repo
- docs(changelog): add human-readable explanations to all entries
- docs(changelog): add detailed v1.1.0 entry with subagent fix explanation
- fix(hooks): allow agent communication tools through session gate
- docs(readme): add context-mode as opt-in feature with full documentation
- feat(hooks): merge context-mode bridge hooks with opt-in flag
- fix(hooks): skip jcodemunch-nudge in projects without jcodemunch
- feat(release): auto-generate CHANGELOG.md on each release
- docs(release): add welcome banner explaining what the script does
- feat(release): auto-create GitHub Release with changelog


### Subagent fix: communication tools no longer blocked

The session gate (`PreToolUse:*`) was blocking ALL tools until indexes were refreshed — including `SendMessage` and `TaskUpdate`. This trapped subagents: they'd finish their work but couldn't return results to the parent agent.

**Before (v1.0.0):** Subagent finishes → tries SendMessage → BLOCKED → sees "run indexes" → re-indexes → tries again → might get blocked again if another agent committed → appears stuck.

**After (v1.0.1):** Agent communication and lifecycle tools always pass through the gate:

| Tool | Why it's allowed |
|------|-----------------|
| `SendMessage` | Subagent needs to return results to parent |
| `TaskUpdate`, `TaskCreate`, `TaskGet`, `TaskList`, `TaskOutput`, `TaskStop` | Agent lifecycle — no code/doc access needed |
| `Agent`, `ExitPlanMode`, `EnterPlanMode` | Orchestration tools |
| `AskUserQuestion` | User interaction |

The gate still enforces index freshness on tools that actually read code (Read, Edit, Write, Bash, Grep, Glob).

### context-mode support (opt-in)

Three hooks merged from [context-mode-jmunch-bridge](https://github.com/shacharbard/context-mode-jmunch-bridge):

| Hook | What it does |
|------|-------------|
| `context-mode-nudge.sh` | Redirects Read on large .json/.html files to `ctx_execute_file` |
| `context-mode-bash-nudge.sh` | Redirects large-output Bash commands (pytest, git log, curl) to `ctx_execute` |
| `track-genuine-savings-ctx.sh` | Tracks context-mode token savings (CTX counter in statusline) |

**Opt-in per project:** Run `init-project.sh --context-mode` to enable. Without the flag, context-mode is not configured and hooks have zero impact — they check `.mcp.json` before doing anything.

### .mcp.json guard on all nudge hooks

All nudge hooks now check if their MCP server is configured in the project's `.mcp.json` before blocking. Projects without jcodemunch or context-mode configured are completely unaffected — Read and Bash work normally.

### Other changes

- **Auto-generate CHANGELOG.md on release** — `release.command` now prepends the new version's changes to CHANGELOG.md automatically
- **GitHub Release created automatically** — `release.command` uses `gh release create` with changelog, no manual step
- **Release script welcome banner** — shows what the script will do before starting, so you know what to expect
- **README updated** — context-mode documented as opt-in feature with a "do I need it?" decision table, updated coverage table, session lifecycle diagram, and subagent instructions

## v1.0.0

First stable release.

- **One-liner installer** — `curl | bash` sets up everything globally, clones to `~/.jmunch-hooks`
- **Per-project init script** — `init-project.sh` creates symlinks, MCP config, tool permissions, and hook registrations in one command
- **Version status on session start** — prints branch, commit hash, and tag after verifying against the remote (silent when throttled)
- **Security: remote URL verification** — auto-update and sync both verify the git remote matches the expected repo before pulling
- **Security: SHA256 checksums** — `CHECKSUMS.sha256` published with every release, verifiable via `sync-hooks.sh --verify`
- **Security: update logging** — every auto-update logs old/new commit hash and changed files to `~/.claude/jmunch-update.log`
- **Stable branch model** — users track `stable` (updated on release only), repo owner works on `main`
- **.gitignore** — prevents `.vbw-planning/`, `CLAUDE.md`, `.mcp.json` from accidentally being committed
- **Symlink-based distribution** — `sync-hooks.sh` creates symlinks to the repo, not copies. `git pull` = instant update everywhere
- **stderr fix** — all 4 PreToolUse hooks now write block messages to stderr (Claude Code only shows stderr to the model on exit 2). Previously wrote to stdout, causing "No stderr output" errors
- **context-mode exception in session gate** — `mcp__context-mode__*` tools now pass through the session gate, preventing a deadlock when context-mode initializes
- **Statusline styling** — bold lilac for JCM/JDM/CTX labels, bright green for today's savings
- **Statusline layout** — rearranged lines for cleaner display (model/time on L3, savings on L4)
- **VBW statusline cache fix** — auto-clears stale slow cache on fetch failure so limits retry immediately after re-login
- **jDocMunch savings estimation** — `track-genuine-savings.sh` now estimates savings for jDocMunch tools that report `tokens_saved=0`, using conservative baselines
- **JSONL history logging** — per-event savings log at `~/.code-index/_genuine_savings_history.jsonl` for daily breakdowns in statusline
