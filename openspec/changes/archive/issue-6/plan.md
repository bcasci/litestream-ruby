Status: archived

## Problem

Upgrading from Litestream v0.3.x (WAL replication) to v0.5.x (LTX replication) orphans the old shadow-WAL trees. The v0.5 binary writes to a new `ltx/` directory inside each database's meta directory and never reads or deletes the old `generations/*/wal/` tree. Those files persist forever as dead weight. In Boswell production this left 755 MB of orphaned files on a 1 GB Fly.io volume — the primary cause of recurring disk exhaustion and `SQLite3::SQLException: cannot rollback - no transaction is active`.

Litestream keeps its metadata beside each database file in `<dir>/.<basename>-litestream/`. Production evidence shows the orphaned data at `.<basename>-litestream/generations/<hex>/wal/`, and the intended signal is: once v0.5 has *actually replicated* (a non-empty `ltx/` exists alongside `generations/`), the `generations/` tree is dead and safe to delete.

There is no code today that removes it. Add an explicit, guarded, operator-run cleanup.

## Pre-implementation gate (blocking)

Before any code is written, verify against real v0.5 evidence (a live post-upgrade volume or the Litestream source) that:

1. v0.5 stores LTX data in `<dir>/.<basename>-litestream/ltx/` — the same meta directory that holds the v0.3 `generations/` tree.
2. A non-empty `ltx/` reliably indicates v0.5 has taken over replication (i.e. the presence of LTX files is a sound "safe to delete generations" signal).

If either is false, the guard is wrong and this plan must be reworked. This is a hard gate, not an aside, because the delete is irreversible (see Risks).

## Acceptance criteria

- [ ] A new `Litestream::Cleanup` module exposes `clean!(dry_run: false)` that enumerates configured databases via `Litestream::Commands.databases`, and for each derives the meta directory `File.join(File.dirname(path), ".#{File.basename(path)}-litestream")`.
- [ ] For a database whose meta directory contains **both** a `generations/` subdirectory **and an `ltx/` subdirectory containing at least one `.ltx` file** (at least one entry), `clean!` deletes the `generations/` subtree.
- [ ] When the meta directory has `generations/` but the `ltx/` subdirectory is **absent or empty**, `clean!` leaves `generations/` untouched — v0.5 has not confirmably replicated yet, so deleting would risk the only local copy.
- [ ] `clean!` never deletes or modifies the `ltx/` directory, the database file, or the meta directory itself — only the `generations/` subtree is removed.
- [ ] A database with no meta directory, or a meta directory with no `generations/`, is skipped without error.
- [ ] `clean!(dry_run: true)` deletes nothing and returns the `generations/` directories it would have removed.
- [ ] `clean!` returns a summary object listing `removed:` (paths deleted, or paths that would be deleted under `dry_run`); the rake task prints this summary. No logger is used in the core path.
- [ ] If one or more deletions fail (e.g. permissions), `clean!` attempts every eligible database first, then raises `Litestream::Cleanup::CleanupFailedException` whose message aggregates **all** failed paths with their underlying reasons and names the paths that were successfully removed, plus a remediation heredoc. It never silently swallows a failure.
- [ ] A new `litestream:cleanup` rake task delegates to `Litestream::Cleanup.clean!`, maps a bare `-dry-run`/`--dry-run` argv flag to `dry_run: true`, and prints the summary. No cleanup logic lives in the task body.
- [ ] `lib/litestream.rb` requires `litestream/cleanup` unconditionally (core, non-Rails).
- [ ] Existing tests still pass (`rake test`); the rake-task "missing assertions" warnings are expected and permitted.

## Test list

New offline unit tests in `test/litestream/test_cleanup.rb`. Each builds a fake meta-directory tree under a `tmp` path it creates and removes in `setup`/`teardown` (testing.md #7), and stubs `Litestream::Commands.databases` to return `[{"path" => <tmp db path>}, ...]` so nothing shells out to the binary (testing.md #3).

- Criterion 2 — meta dir with `generations/<hex>/wal/` and a non-empty `ltx/` (one file): `clean!` removes the `generations/` tree; assert `Dir.exist?(generations)` is false.
- Criterion 3a (no ltx) — meta dir with `generations/` but no `ltx/`: `generations/` still exists after `clean!`.
- Criterion 3b (empty ltx) — meta dir with `generations/` and an **empty** `ltx/`: `generations/` still exists after `clean!` (guards the boot-before-first-replication window).
- Criterion 4 — after a successful delete, assert the `ltx/` dir, the db file, and the meta dir itself all still exist.
- Criterion 5a — db path with no meta dir: `clean!` returns an empty `removed:` list and raises nothing.
- Criterion 5b — meta dir present but no `generations/`: skipped, nothing removed, no error.
- Criterion 6 — two configured dbs (one eligible, one with empty `ltx/`): only the eligible db's `generations/` is removed; the summary's `removed:` lists exactly that one path.
- Criterion 6 (derivation) — a db at `<tmp>/storage/app.sqlite3` maps to meta dir `<tmp>/storage/.app.sqlite3-litestream`; assert the derived path.
- Criterion 7 (dry-run) — `dry_run: true`: the eligible `generations/` dir still exists and the summary's `removed:` lists it as would-be-removed.
- Criterion 8a (single failure) — stub the deletion to raise `Errno::EACCES`; assert `CleanupFailedException` whose message includes the failed path and reason.
- Criterion 8b (multiple failures) — two eligible dbs both fail deletion; assert the single raised `CleanupFailedException` aggregates both paths and both reasons.

Task tests in `test/tasks/test_litestream_tasks.rb` (mirroring the existing `Minitest::Mock` delegation tests; add `Rake::Task["litestream:cleanup"].reenable` to `setup`):

- Criterion 9a — `rake litestream:cleanup` invokes `Litestream::Cleanup.clean!` with `dry_run: false` (mock `.expect` + `.verify`).
- Criterion 9b — set `ARGV` to `["litestream:cleanup", "--", "-dry-run"]` so the real `parse_argv_options` runs, and assert `clean!` is invoked with `dry_run: true`.

- Criterion 10 — `rake test` passes.

## Approach + files

- `lib/litestream/cleanup.rb` (new) — `module Litestream::Cleanup` with `class << self`:
  - `CleanupFailedException = Class.new(StandardError)` with a `# raised when a generations/ directory could not be deleted` comment (error-handling.md #1).
  - `clean!(dry_run: false)`:
    - Enumerate `Litestream::Commands.databases`; for each `db["path"]` compute `meta = File.join(File.dirname(path), ".#{File.basename(path)}-litestream")`, `generations = File.join(meta, "generations")`, `ltx = File.join(meta, "ltx")`.
    - Eligible when `Dir.exist?(generations)` **and** `Dir.exist?(ltx)` **and** `!Dir.empty?(ltx)`.
    - For each eligible dir: under `dry_run`, record it; otherwise `FileUtils.rm_r(generations, secure: true)` (use `rm_r`, which **raises** `SystemCallError` on failure — not `rm_rf`, which swallows), rescuing `SystemCallError` into a collected `failures` list and continuing.
    - After the loop: if `failures` is non-empty, raise `CleanupFailedException` with a `<<~` heredoc aggregating each failed path + reason, naming the successfully removed paths, and giving remediation (see below).
    - Return a summary object with `removed:` (deleted paths, or would-delete paths under `dry_run`).
  - Remediation heredoc content (error-handling.md #3): the failed path(s), then exact recovery commands and a link, e.g.

    ```
    Could not delete orphaned Litestream v0.3 data at:
      <path>
    Reason: <errno message>

    Free the space manually after confirming v0.5 replication is healthy:
        ls -la <meta-dir>
        rm -rf <path>

    See https://github.com/fractaledmind/litestream-ruby/issues/6
    ```
- `lib/litestream.rb` — add `require_relative "litestream/cleanup"` in the unconditional core block at the bottom (alongside `commands`).
- `lib/tasks/litestream_tasks.rake` — add `desc` + `task cleanup: :environment`:
  - `options = parse_argv_options`
  - `dry_run = options.key?(:"-dry-run") || options.key?(:"--dry-run")`
  - `summary = Litestream::Cleanup.clean!(dry_run: dry_run)` then `puts` the summary. Thin body only (structure.md #6).
- `test/litestream/test_cleanup.rb` (new) and `test/tasks/test_litestream_tasks.rb` (extend) — per the Test list.

Enumeration source: `Litestream::Commands.databases` (not raw YAML parsing) — reuses the binary's config resolution and env expansion, matches the existing `Litestream.databases` pattern, and keeps one config scheme (structure.md #8). The meta-dir location is derived purely from each returned path.

Logging: the core path uses no logger (none exists for non-Rails core code; `Commands` only does `puts … if ENV["DEBUG"]`). `clean!` returns the summary; the rake task prints it. This keeps the contract assertable (testing.md #5) without inventing a logging mechanism (structure.md #8).

## Out of scope / gated

- **Automatic invocation on Puma boot.** Deferred — recommend not adding it in this change. Running an irreversible delete on every boot is riskier and harder to test than an explicit operator-run task, and the non-empty-`ltx/` guard already makes the task safe to run once post-upgrade. If you want it, the follow-up is to wire `Litestream::Cleanup.clean!` into `lib/puma/plugin/litestream.rb` behind a **default-off** `Litestream.cleanup_on_boot` flag. Left as your call at the gate.
- Deleting the whole `.<basename>-litestream` meta directory, or the `ltx/` tree — never; only `generations/` is removed.
- Cleaning databases not present in the Litestream config.
- Re-verifying that `generations/` data reached S3/B2 before deleting — the non-empty-`ltx/` guard is the sound-replication signal established in the pre-implementation gate; a separate replica check is not attempted.

Task name is **decided**: `litestream:prune_v0_3_generations` — `prune` (removes dead data) + the literal `v0.3` series marker + the exact `generations/` directory it targets. (The issue's suggested `litestream:cleanup_v3_shadow_wal` mislabels v0.3 as "v3".)

## Risks

- **On-disk layout assumption.** The guard rests on v0.5 writing a non-empty `ltx/` into the same `.<basename>-litestream` meta dir that holds `generations/`. Matches production evidence but is closed only by the blocking Pre-implementation gate above — if that verification fails, the plan is wrong.
- **Irreversible deletion.** `generations/` removal cannot be undone. The non-empty-`ltx/` check is the only safety guard. It closes the empty-`ltx/`-on-boot window (criterion 3b), but a volume where LTX files exist yet the S3 upload never succeeded could still lose the only local pre-upgrade WAL. The issue asserts this data is dead under v0.5; the operator-run (not automatic) design keeps a human in the loop.
- **`Commands.databases` dependency.** Enumeration needs the bundled binary and a readable config; with no/unreadable config it enumerates nothing and cleans nothing — a safe no-op, but silent. The printed summary (empty `removed:`) makes that observable.
- **Relative db paths.** `Commands.databases` returns paths as Litestream resolves them; the meta dir is derived from that same path, so relative-vs-absolute stays consistent with where the binary wrote the files.
