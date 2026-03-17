# Changelog

All notable changes to this project are documented here.
Updated automatically on each release.

## v1.1.0

### Subagent fix: communication tools no longer blocked

The session gate (`PreToolUse:*`) was blocking ALL tools until indexes were refreshed — including `SendMessage` and `TaskUpdate`. This trapped subagents: they'd finish their work but couldn't return results to the parent agent.

**Before (v1.0.0):** Subagent finishes → tries SendMessage → BLOCKED → sees "run indexes" → re-indexes → tries again → might get blocked again if another agent committed → appears stuck.

**After (v1.1.0):** Agent communication and lifecycle tools always pass through the gate:

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

- feat(release): auto-generate CHANGELOG.md and GitHub Release on each release
- docs(readme): add context-mode as opt-in feature with decision table
- docs(release): add welcome banner to release.command

## v1.0.0

First stable release.

- feat(install): add one-liner installer for zero-friction setup
- feat(scripts): add init-project.sh for one-command project setup
- fix(hooks): only print version status after a real remote check
- feat(hooks): show version status on every session start
- docs(readme): add security section with trust model and verification guide
- feat: add stable branch model and .gitignore
- feat(security): add remote verification, checksums, and update logging
- feat(hooks): add sync-hooks.sh and auto-update for zero-maintenance distribution
- fix(hooks): write block messages to stderr so model can see them
- fix(statusline): auto-clear VBW slow cache on fetch failure
- style(statusline): bold lilac for JCM/JDM/CTX labels, bright green for today
- refactor(statusline): rearrange lines for cleaner layout
- feat(hooks): add JDM savings estimation and JSONL history logging
