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

- Non-code files (JSON, MD, HTML, YAML, config)
- Full file context needed (imports, globals, module-level flow)
- Very small files (<50 lines)
- Files not yet indexed (newly created before next `index_folder`)
- Editing 6+ functions in the same file (batch edit — full Read is cheaper)

### Why this matters

Reading a full file consumes the entire content as tokens. `get_symbol` returns only the function body — typically 85-98% fewer tokens. This preserves context window for conversation history and reasoning.

## Documentation Navigation — jDocMunch (MANDATORY when available)

When jDocMunch MCP tools (`mcp__jdocmunch__*`) are available in a project, they are the **primary tool for exploring documentation files** (`.md`, `.mdx`, `.rst`). Do NOT use `Read` on large documentation files unless you explicitly need the full document.

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

- Small documentation files (<50 lines)
- Non-doc files (JSON, YAML, config, code)
- Full document context needed (cross-references, overall structure)
- Files not yet indexed (newly created before next `index_local`)
- CLAUDE.md and other instruction files (always read fully)
