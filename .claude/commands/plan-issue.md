---
description: Draft an implementation plan for a GitHub issue into openspec/changes/ (review gate, no code).
argument-hint: [issue-number]
---

Plan issue #$1. Do not write or change any code, and do not branch.

1. **Inspect** — `gh issue view $1`. Read the code the issue touches. Read `docs/standards/` so the plan conforms. If the change touches an external API (Puma, Litestream config, a gem), pull current docs with `context7`.
2. **Draft** — Write `openspec/changes/issue-$1/plan.md` with these sections:
   - `Status: draft`
   - Problem
   - Acceptance criteria (testable checklist)
   - Test list (one test per criterion)
   - Approach + files
   - Out of scope / gated
   - Risks
3. **Vet** — Use the `plan-reviewer` subagent to vet `openspec/changes/issue-$1/plan.md`. If its verdict is `NEEDS-REVISION`, fix every issue it raises and vet again. Stop after 2 revision rounds; move any still-unresolved concern into the plan's Risks section.
4. **GATE** — Show the vetted plan and wait for my reply. On my approval: set `Status: approved`, then commit only that file (`git add openspec/changes/issue-$1/plan.md && git commit`).

Local only. Do not run `/apply-plan` — I will.
