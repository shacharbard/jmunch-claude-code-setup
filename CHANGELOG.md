# Changelog

All notable changes to this project are documented here.
Updated automatically on each release.

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
