# Memory maintenance (always loaded, keep tiny)

This project uses a tiered, token-efficient memory system. Keep it that way:

- **`CLAUDE.md`** = always-loaded core. Stable facts only (identity, architecture, LOCKED conventions,
  commands). Target under ~150 lines. If it grows, push detail into a path-scoped rule.
- **`.claude/rules/*.md`** = detail that loads only when touching matching files (via `paths` frontmatter).
  Put package- or domain-specific guidance here, not in CLAUDE.md.
- **`.claude/STATE.md`** = the living ledger (current phase, what's done, what's next, decisions). Update
  it as work lands. Read it at session start. Summarize; don't paste logs or diffs.
- **Auto memory** (`~/.claude/projects/<project>/memory/MEMORY.md`) = machine-local learnings Claude writes
  itself. Fine for incidental discoveries; canonical project facts belong in the git-tracked files above.

Rules of thumb: prefer summaries over raw history; reference big files by path instead of `@import`-ing
them (imports cost launch tokens); when you learn a durable fact, record it in the right tier and prune
anything now stale. One source of truth per fact - if two files disagree, fix it.
