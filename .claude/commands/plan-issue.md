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
3. **Vet loop** — Repeat until the `plan-reviewer` subagent returns `VERDICT: READY`, or you have done 2 revise-and-re-vet cycles:
   - Run the `plan-reviewer` subagent on `openspec/changes/issue-$1/plan.md`.
   - `READY` → exit the loop.
   - `NEEDS-REVISION` → fix every issue it raised, then re-run.
   If still `NEEDS-REVISION` after 2 cycles, move each unresolved issue into the plan's Risks section and flag it for my judgment.
4. **GATE** — Show the vetted plan (and its final verdict) and wait for my reply. On my approval: set `Status: approved`, then commit only that file (`git add openspec/changes/issue-$1/plan.md && git commit`).

Local only. Do not run `/apply-plan` — I will.
