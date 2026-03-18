# Global Instructions

Add this content to your `~/.claude/CLAUDE.md` file.

## Code Navigation — jCodeMunch (MANDATORY when available)

When jCodeMunch MCP tools (`mcp__jcodemunch__*`) are available in a project, they are the **primary tool for all Python/TypeScript code exploration**. Do NOT use `Read` on `.py`, `.ts`, or `.tsx` files unless you explicitly need full file context.

### Rules

- **ALWAYS** use `get_symbol` to fetch specific functions/classes — never read an entire file to find one function
- **ALWAYS** use `search_symbols` instead of `Grep` when looking for function/class definitions — skip `get_file_outline` when you already know the name
- **ALWAYS** run `index_folder` (incremental) at the start of each session to keep the index fresh
- **ALWAYS** re-run `index_folder` after compaction/autocompact to refresh the index with any files changed during the session
- **Sliced edit workflow (CRITICAL):** To edit a function, do NOT read the full file. Instead: `get_symbol` (find line range) → `get_file_content(start_line=line-4, end_line=end_line+3)` → `Edit`. This saves ~85% vs full Read.
- For 6+ functions in the same file, full `Read` is cheaper — skip jCodeMunch
- Fall back to `Read` ONLY for non-code files (JSON, MD, HTML, config) or when full file context is explicitly required
- When delegating to subagents, direct them to specific symbols and include jCodeMunch instructions + sliced edit workflow in prompts
- Subagents MUST follow these same rules — include jCodeMunch instructions in agent prompts

### When Read is correct

- Non-code files (YAML, small config) — but route docs/structured files to jDocMunch and data files to context-mode
- Full file context needed (imports, globals, module-level flow)
- Very small files (<50 lines)
- Files not yet indexed (newly created before next `index_folder`)
- Editing 6+ functions in the same file (batch edit — full Read is cheaper)

### Why this matters

Reading a full file consumes the entire content as tokens. `get_symbol` returns only the function body — typically 85-98% fewer tokens. This preserves context window for conversation history and reasoning.

## Documentation Navigation — jDocMunch (MANDATORY when available)

When jDocMunch MCP tools (`mcp__jdocmunch__*`) are available in a project, they are the **primary tool for exploring documentation and structured files** (`.md`, `.mdx`, `.rst`, `.adoc`, `.txt`, `.ipynb`, `.html`, `.json`, `.jsonc`, `.xml`, `.svg`, `.xhtml`, `.tscn`, `.tres`). Do NOT use `Read` on large documentation or structured files unless you explicitly need the full document.

### Rules

- **ALWAYS** use `search_sections` to find relevant documentation sections — never read an entire doc to find one section
- **ALWAYS** use `get_toc` or `get_toc_tree` to understand a document's structure before reading it
- **ALWAYS** use `get_section` to retrieve specific sections by ID — not full file reads
- **ALWAYS** run `index_local` at the start of each session to keep the doc index fresh
- **ALWAYS** re-run `index_local` after compaction/autocompact to refresh the index with any docs changed during the session
- Fall back to `Read` ONLY for small docs (<50 lines), non-indexed file types, or when full document context is explicitly required
- When delegating to subagents, direct them to specific sections (e.g., "search for 'authentication' in docs using jDocMunch `search_sections`") rather than telling them to read whole files
- Subagents MUST follow these same rules — include jDocMunch instructions in agent prompts

### When Read is correct

- Small documentation/structured files (<50 lines)
- Non-indexed file types (YAML, TOML, CSV, code files)
- Full document context needed (cross-references, overall structure)
- Files not yet indexed (newly created before next `index_local`)
- CLAUDE.md and other instruction files (always read fully)

## Command Output & Data File Navigation — context-mode (when available)

When context-mode MCP tools (`mcp__context-mode__*`) are available, use them for **large command outputs** and **data files that need code-based processing** instead of letting raw content flood the context window.

### Command Output Isolation (primary use case)

Use `ctx_execute(language="shell", code="...")` instead of `Bash` for commands that produce large output:

- **Test suites:** `ctx_execute(language="shell", code="pytest ...")` — not `Bash("pytest ...")`
- **git log/diff (unbounded):** `ctx_execute(language="shell", code="git log ...")` — not `Bash("git log")`
- **Recursive search:** `ctx_execute(language="shell", code="find . -name ...")` — not `Bash("find ...")`
- **API calls:** `ctx_execute(language="shell", code="curl ...")` — not `Bash("curl ...")`
- **Build output:** `ctx_execute(language="shell", code="make ...")` — not `Bash("make ...")`

Outputs >5KB are automatically filtered by intent — only relevant portions enter context (98% savings).

**When Bash IS correct:** git status/add/commit/push, file management (ls/mkdir/mv/cp), package installs, inline one-liners, commands with output redirected to a file.

### Data File Rules

- **JSON arrays needing filtering/transformation** (data dumps, log arrays): Use `ctx_execute_file(path, language, code)` — file content available as `FILE_CONTENT` variable
- **Structured JSON** (object with named keys, API specs, config): Use **jDocMunch** `search_sections` / `get_section` instead
- **HTML with headings** (documentation-like): Use **jDocMunch** — it parses heading structure
- **HTML without headings** (raw data tables, generated output): Use `ctx_execute_file`
- **CSV, TOML files needing processing:** Use `ctx_execute_file`
- **Index a file for search:** Use `ctx_index(path="file.json", source="label")`
- **Batch operations:** Use `ctx_batch_execute(commands=[...], queries=[...])` — runs commands AND searches in one call
- **Search previous outputs:** Use `ctx_search(queries=["terms"])`
- **Index external docs:** Use `ctx_fetch_and_index` for URLs, then `ctx_search` to query
- **Small config JSON** (package.json, tsconfig.json, <100 lines): Direct Read is fine

### Four-tier navigation

1. **Code** (.py/.ts/.tsx) → jCodeMunch (`get_symbol`, `search_symbols`)
2. **Docs & structured files** (.md, .mdx, .rst, .adoc, .txt, .ipynb, .html, .json, .jsonc, .xml, .svg, .xhtml, .tscn, .tres) → jDocMunch (`search_sections`, `get_section`)
3. **Data processing** (JSON arrays, CSV, TOML, large command outputs, test suites, build logs) → context-mode (`ctx_execute_file`, `ctx_execute`)
4. **Small config** (package.json, tsconfig.json, <50-100 lines) → Read directly

### When Bash/Read is correct (not context-mode)

- Small commands with predictable output (git status, ls, pwd, echo)
- Git operations that modify state (add, commit, push, checkout)
- Package installs (npm install, pip install)
- Small JSON/HTML files (<100 lines) or config files
- Files that need full context for editing (e.g., known_verdicts.json)
- Code files → use jCodeMunch instead
- Doc/structured files → use jDocMunch instead
