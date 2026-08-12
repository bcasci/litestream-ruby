---
description: Draft an implementation plan for a GitHub issue into openspec/changes/ (review gate, no code).
argument-hint: [issue-number]
---

Plan issue #$1. Do not write or change any code, and do not branch.

1. **Inspect** — `gh issue view $1`. Read the code the issue touches.
2. **Draft** — Write `openspec/changes/issue-$1/plan.md` with these sections:
   - `Status: draft`
   - Problem
   - Acceptance criteria (testable checklist)
   - Test list (one test per criterion)
   - Approach + files
   - Out of scope / gated
   - Risks
3. **GATE** — Show the plan and wait for my reply. On my approval: set `Status: approved`, then commit only that file (`git add openspec/changes/issue-$1/plan.md && git commit`).

Local only. Do not run `/apply-plan` — I will.
