# openspec/ — change plans (stop-gap)

Manual, OpenSpec-shaped change tracking, in source, until we adopt
[OpenSpec](https://github.com/Fission-AI/OpenSpec) (after claude-flow is removed).

- `changes/issue-<N>/plan.md` — an approved, in-flight change plan.
- `changes/archive/issue-<N>/plan.md` — a completed, archived change.

Lifecycle (Claude Code commands):

1. `/plan-issue <N>` — draft `changes/issue-<N>/plan.md`, review, approve.
2. `/apply-plan <N>` — implement the approved plan (TDD, local branch, ff-merge).
3. `/archive-plan <N>` — move the plan to `archive/` after the merge.

Each `plan.md` carries a `Status:` line (`draft` → `approved` → `archived`).
`/apply-plan` refuses a plan that is not `approved`.

Migration: when we take on OpenSpec, `changes/` moves under its layout and these
three commands are replaced by `/opsx:propose`, `/opsx:apply`, `/opsx:archive`.
