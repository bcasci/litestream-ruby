---
description: Implement an approved plan from openspec/changes/ with TDD, locally.
argument-hint: [issue-number]
---

Implement the plan at `openspec/changes/issue-$1/plan.md`.

1. **Precheck** — Read the plan. If its `Status:` is not `approved`, stop and say so. Do not proceed.
2. **Branch** — `git checkout main`, then `git checkout -b fix/issue-$1-<slug>`.
3. **TDD** — For each acceptance item in the plan: write one failing test, run it and confirm it fails, write the minimum code to pass it, then refactor. Follow `docs/standards/`.
4. **Verify** — Run `ASDF_RUBY_VERSION=3.3.8 bundle exec rake test` and `ASDF_RUBY_VERSION=3.3.8 bundle exec standardrb`. Both must be green.
5. **Review** — Run `/code-review` on the diff. Fix real findings, then re-run step 4.
6. **Merge** — Commit the work. **GATE: wait for my approval.** Then `git checkout main && git merge --ff-only fix/issue-$1-<slug>` and delete the branch.

Local only: no push, no PR, no tag, no release. When done, tell me to run `/archive-plan $1`.
If any step fails, stop and report it. Do not work around a failure.
