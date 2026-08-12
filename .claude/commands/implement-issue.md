---
description: Implement a GitHub issue locally with a plan-approval gate and TDD (red-green-refactor).
argument-hint: [issue-number]
---

Implement issue #$1 locally. Run the steps in order. Do not skip, reorder, or combine them. Stop at each **GATE** and wait for my reply.

1. **Inspect** — `gh issue view $1`. Read the code it touches. Write the acceptance criteria as a testable checklist.
2. **Plan** — Write `tmp/issue-$1-plan.md` with these sections: Problem; Acceptance criteria (checklist); Test list (one test per criterion); Approach + files; Out of scope / gated; Risks. **GATE: show the plan and wait for my approval. Write no code before I approve.**
3. **Branch** — `git checkout main`, then `git checkout -b fix/issue-$1-<slug>`.
4. **TDD** — For each acceptance item: write one failing test, run it and confirm it fails, write the minimum code to pass it, then refactor. Follow `docs/standards/`.
5. **Verify** — Run `ASDF_RUBY_VERSION=3.3.8 bundle exec rake test` and `ASDF_RUBY_VERSION=3.3.8 bundle exec standardrb`. Both must be green before continuing.
6. **Review** — Run `/code-review` on the diff. Fix real findings, then re-run step 5.
7. **Merge** — Commit the branch work. **GATE: wait for my approval.** Then `git checkout main && git merge --ff-only fix/issue-$1-<slug>` and delete the branch.

Constraints:

- Local only: no `git push`, no PR, no tag, no release, no `gh issue close`.
- If any step fails, stop and report it. Do not work around a failure.
