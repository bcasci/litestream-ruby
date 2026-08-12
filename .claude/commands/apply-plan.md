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
6. **PR** — Commit the branch work and push it. If there is no open PR for the branch, open one with `gh pr create --base main` — title referencing the issue; body covering the changes, verification, and any gated follow-up; `Refs #$1` (use `Closes #$1` only if this change fully satisfies the issue). Report the PR URL. Do not merge — I review and merge the PR.

No tag, no release, no `gh issue close`. After the PR merges, run `/archive-plan $1`.
If any step fails, stop and report it. Do not work around a failure.
