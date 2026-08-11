---
name: litestream-standards
description: Enforces the litestream-ruby coding standards in docs/standards/ (structure, naming, error handling, testing, Ruby idioms, extensibility). Use whenever writing, editing, refactoring, testing, or reviewing Ruby code in this gem, and before finishing any change under lib/, app/, exe/, config/, lib/tasks/, or test/. Triggers on editing Ruby, adding a command or controller or job, writing a test, reviewing a diff, or asking whether a change follows the project's standards.
---

# litestream-ruby Coding Standards

Apply these standards to every code change, test, and review in this gem. They are enforced, not optional. The linter (`standardrb`) is the floor; this skill carries the organization, naming, and architecture the linter can't see.

## When this applies

Any edit under `lib/`, `app/`, `exe/`, `config/`, `lib/tasks/`, or `test/`; any code review; any new subcommand, controller, job, generator, or test.

## How to use

1. Read the relevant standard before editing:
   - Where code goes, namespacing, separation → `docs/standards/structure.md`
   - Naming (name things what they are) → `docs/standards/naming.md`
   - Typed exceptions & remediation → `docs/standards/error-handling.md`
   - Minitest, stubbing, isolation → `docs/standards/testing.md`
   - Ruby idioms beyond the linter → `docs/standards/ruby-idioms.md`
   - API, versioning, deprecation → `docs/standards/extensibility.md`
2. Match the patterns already in the codebase — don't invent a new mechanism.
3. Before finishing, self-review against the checklist below. Fix violations now; don't defer them.
4. Run `ASDF_RUBY_VERSION=3.3.8 bundle exec standardrb` and `ASDF_RUBY_VERSION=3.3.8 bundle exec rake test`. Both must pass.

## Pre-finish checklist

- [ ] Namespaced under `Litestream::` (except the Puma plugin).
- [ ] `# frozen_string_literal: true` on line 1 of every `.rb` file.
- [ ] Names say what the thing is; no name left lying.
- [ ] One responsibility per file; new logic in the right layer (`Commands` / config / `Upstream` / `Engine`).
- [ ] New failure modes use typed exceptions with a `# raised when …` comment and a remediation message.
- [ ] Required args guarded at entry with a copy-pasteable example.
- [ ] Shell-outs built as arrays, never interpolated strings.
- [ ] Tests stub every external call (binary, systemctl/ps, network); global state reset in teardown.
- [ ] `assert_equal expected, actual` order.
- [ ] Public API changes go through `Litestream.deprecator` + a `**BREAKING**` CHANGELOG entry.
- [ ] `standardrb` and `rake test` pass.

When reviewing code, report each violation against the specific rule and file it breaks. Don't approve a change that fails the checklist.
