---
description: Archive a completed change — move its plan to openspec/changes/archive/ and commit.
argument-hint: [issue-number]
---

Archive the completed change for issue #$1.

1. Confirm the PR for #$1 is merged. If not, stop and say so.
2. `git checkout main && git pull` (get the merged PR).
3. `git mv openspec/changes/issue-$1 openspec/changes/archive/issue-$1`.
4. In the moved `plan.md`, set `Status: archived`.
5. Commit: `git add -A openspec/changes && git commit`.

Local only.
