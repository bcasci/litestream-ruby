---
name: plan-review
description: Vets an implementation plan (an openspec/changes/<id>/plan.md) for gaps, untestable acceptance criteria, standards violations, and scope creep before it is approved. Use when reviewing or vetting a plan, or from the plan-reviewer subagent. Trigger with phrases like "vet the plan", "review this plan", "check the plan for issues".
allowed-tools: "Read, Grep, Glob, Bash(gh:*)"
---

# Plan Review

Vet the plan at the given path against its issue and `docs/standards/`. First read the plan, `gh issue view <N>`, the code it touches, and the relevant `docs/standards/` files. Then check each:

1. **Acceptance criteria** — each is testable and measurable; together they cover everything the issue asks (compare against the issue).
2. **Test list** — one test per criterion, failure paths included, matching `docs/standards/testing.md`.
3. **Approach + files** — files match `docs/standards/structure.md`; minimal; conforms to the naming, error-handling, and extensibility standards; no scope creep.
4. **Scope / gates** — release/publish and other out-of-scope work is explicitly gated, not silently included.
5. **Risks** — real risks named: back-compat, migration, the Ruby >= 3 / Rails >= 7 matrix, the gem-vs-upstream two-version scheme where relevant.
6. **Gaps** — missing edge cases, unaddressed asks from the issue, unstated assumptions.
7. **Right-sizing** — not over-engineered, not under-specified.

Output:

- A numbered list of concrete issues. Each: the problem — where in the plan — the fix.
- Then one final line: `VERDICT: READY` or `VERDICT: NEEDS-REVISION`.

Default to `NEEDS-REVISION` if any acceptance criterion is untestable or any standard is violated. If the plan is sound, return `VERDICT: READY` with no padding.
