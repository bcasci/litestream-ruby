# Coding Standards

Enforced conventions for this gem. The linter is the floor; these cover the organization, naming, and architecture it can't see.

**Prime directive:** name things what they are, one responsibility per file, fail with typed exceptions + remediation, stub every external call in tests.

## The standards

- [Structure & organization](structure.md) — where code goes, namespacing, separation of concerns
- [Naming](naming.md) — name things what they are
- [Error handling & messages](error-handling.md) — typed exceptions, actionable remediation
- [Testing](testing.md) — Minitest, stubbing, isolation
- [Ruby idioms](ruby-idioms.md) — judgment calls beyond `standardrb`
- [Extensibility, API & versioning](extensibility.md) — evolving the gem safely

## How they're enforced

1. **Always in context** — a pointer in the root `CLAUDE.md`.
2. **Skill** (`.claude/skills/litestream-standards/`) — auto-loads when writing, testing, or reviewing Ruby here; carries the judgment layer and a pre-finish checklist.
3. **`standardrb` gate** — a `PostToolUse` hook (`.claude/hooks/standardrb-gate.sh`) that blocks on lint violations in edited `.rb` files.

Each rule earned its place from a pattern already in the codebase. Add a rule only when a real convention needs stating; delete one when it stops being true.
