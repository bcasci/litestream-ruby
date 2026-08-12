Status: archived

## Problem

`Litestream::Commands.execute` only raises `CommandFailedException` when the parsed result is a **tabular** Array whose single row has `level == "ERROR"` (`lib/litestream/commands.rb:180`). For **non-tabular** commands — `restore` runs with `tabled_output: false` (`commands.rb:147`) — `run` returns the raw stdout String (`commands.rb:205`), `Array === results` is false, and `execute` returns it as success. Nothing checks the child process exit status.

So a failed `restore` (non-zero exit: wrong path, missing/corrupt replica, bad credentials) returns normally. `RestorationsController#create` then renders "Restored to `<backup>`" with a 200 — a silent data-safety false positive on the disaster-recovery path. Worse, `run` captures only stdout via `IO.popen(cmd)`; litestream writes errors to **stderr**, so the returned String is often empty on failure.

Fix: detect a non-zero child exit in `run` and raise `CommandFailedException` with the command and the stderr reason, for every command — closing the non-tabular gap while preserving the existing tabular-ERROR detection. Combined with #8's controller rescue (which catches `CommandFailedException`), a failed restore then surfaces the remediation alert instead of a false success.

## Acceptance criteria

- [ ] `run` executes the command with `Open3.capture3(*cmd)` — an argv array, no shell — preserving the no-shell-interpolation property established in #8 (ruby-idioms 5).
- [ ] When the child exits non-zero, `run` raises `Litestream::Commands::CommandFailedException` whose message embeds the command (`cmd.join(" ")`) and a reason taken from stderr, falling back to stdout when stderr is blank. This fires for **both** tabular and non-tabular commands (checked before any tabular parsing).
- [ ] On a zero-exit (success) run, return shapes are unchanged: raw `chomp`ed stdout String for `tabled_output: false`; array-of-hashes for `tabled_output: true`.
- [ ] `Commands.restore` raises `CommandFailedException` when its child exits non-zero (previously returned a String as success).
- [ ] `execute`'s existing exit-0-with-`level == "ERROR"` tabular detection still raises `CommandFailedException` (kept as a secondary guard for the case where litestream prints an ERROR row but exits 0).
- [ ] A missing executable still raises `SystemCallError` (`Errno::ENOENT`) out of `run` (Open3 raises it as `IO.popen` did), so `RestorationsController#create`'s `SystemCallError` rescue (#8) keeps catching it.
- [ ] The other command wrappers (`databases`, `generations`, `ltx`) keep working on success and now raise on a non-zero exit as well; `run_replicate` is unchanged.
- [ ] **End-to-end:** a failed restore driven through the real `restore` → `execute` → `run` chain (child exits non-zero) reaches `RestorationsController#create`'s rescue, which redirects with an `alert:` flash and **no** `notice:` — the exact false-success symptom the issue reports, now fixed.
- [ ] `rake test` and `standardrb` are both green.

## Test list

New/updated tests in `test/litestream/test_commands.rb` (the `TestRunExecution` class calls real `run`; every other command test stubs `:run` and is unaffected). A small fake status object responding to `success?` stands in for `Process::Status`; `Open3.capture3` is stubbed so nothing shells out (testing.md #3).

- **Criterion 2 (non-tabular failure)** — stub `Open3.capture3` → `["", "restore failed: no such database", status(false)]`; `Commands.send(:run, [exe, "restore"], tabled_output: false)` raises `CommandFailedException`; assert the message includes the reason (`no such database`) and the command.
- **Criterion 2 (tabular failure)** — same non-zero status with `tabled_output: true`: `assert_raises(CommandFailedException)` (it raises before parsing, not returns a parsed Array).
- **Criterion 2 (stderr-blank fallback)** — stub → `["boom on stdout", "", status(false)]`; assert the raised reason falls back to stdout (`boom on stdout`).
- **Criterion 2 (stderr wins when both present)** — stub → `["stdout text", "stderr text", status(false)]`; assert the raised reason is the stderr text, not stdout.
- **Criterion 3 (success tabular)** — stub → `["name  replicas\ndb    s3", "", status(true)]`; `run(..., tabled_output: true)` returns `[{"name"=>"db","replicas"=>"s3"}]`. (rewrite of the existing `IO.popen`-stub test.)
- **Criterion 3 (success raw)** — stub → `["raw restore output\n", "", status(true)]`; `run(..., tabled_output: false)` returns `"raw restore output"`. (rewrite of the existing test.)
- **Criterion 4 (restore integration)** — within the `TestCommands` harness (which stubs `:executable`), stub `Open3.capture3` to a non-zero status; `Commands.restore("db/test.sqlite3")` raises `CommandFailedException`.
- **Criterion 5 (execute ERROR row preserved)** — stub `:run` to return `[{"level" => "ERROR", "error" => "boom"}]`; `Commands.send(:execute, "databases")` raises `CommandFailedException` embedding `boom`. (Covers the pre-existing branch that currently has no test.)
- **Criterion 6 (missing executable)** — stub `Open3.capture3` to raise `Errno::ENOENT`; assert `run` lets the `SystemCallError` propagate (not swallowed into a false success).
- **End-to-end (controller)** — in `test/controllers/test_restorations_controller.rb`, drive the real restore path: stub `Litestream::Commands.executable` to a dummy string and `Open3.capture3` to a non-zero status, then `POST litestream.restorations_url`. Assert `assert_redirected_to litestream.root_path`, `flash[:alert]` is set (includes the remediation clause), and `flash[:notice]` is nil — proving the failed restore no longer renders "Restored to …". (Distinct from #8's tests, which stub `Commands.restore` to raise; this one exercises `restore → execute → run → raise`.)
- **Criterion 8** — `rake test` passes (rake-task "missing assertions" warnings expected).

## Approach + files

- `lib/litestream/commands.rb`:
  - `require "open3"` at the top (beside the existing requires).
  - Rewrite `run`:
    ```ruby
    def run(cmd, tabled_output:)
      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        reason = stderr.strip.empty? ? stdout.strip : stderr.strip
        raise CommandFailedException, "Failed to execute `#{cmd.join(" ")}`; Reason: #{reason}"
      end

      stdout = stdout.chomp
      return stdout unless tabled_output

      keys, *rows = stdout.split("\n").map { _1.split(/\s+/) }
      rows.map { keys.zip(_1).to_h }
    end
    ```
  - Leave `execute` unchanged (its `level == "ERROR"` check stays as the exit-0 secondary guard) and `run_replicate` unchanged.
- `test/litestream/test_commands.rb` — update `TestRunExecution` to stub `Open3.capture3` instead of `IO.popen`, and add the failure / restore / execute-ERROR / ENOENT tests above. Add a `status(bool)` helper returning an object that answers `success?`. **Note:** `TestRunExecution < TestCommands` inherits the `run` instance method Minitest uses as its per-test wrapper (`test_commands.rb:7`); name the helper `status` and do not add any helper named `run`, or every test in the class breaks.
- `test/controllers/test_restorations_controller.rb` — add the end-to-end failed-restore test above (alongside the #8 tests).

Keeping the exit-status check inside `run` (co-located with the exec and its status) means `execute` never inspects the global `$?`; the many tests that stub `:run` see no change (they return canned success values), avoiding the non-deterministic-`$?` pitfall the issue calls out.

## Out of scope / gated

- `run_replicate` / the `replicate` streaming path — it intentionally streams output live and is long-running; exit-status handling there is a separate concern.
- Reworking `execute`'s tabular ERROR-row detection — kept as-is (secondary guard).
- Surfacing stderr in the dashboard UI beyond the `CommandFailedException` message that the #8 controller rescue already renders.
- Any gem/upstream version bump.

## Risks

- **Capture mechanism change (`IO.popen` → `Open3.capture3`).** #8 moved `run` to `IO.popen(cmd)`; this moves it to `Open3.capture3(*cmd)` — still argv-form, no shell, so ruby-idioms 5 holds. `capture3` buffers stdout+stderr to memory; this is no worse than the prior `IO.popen(cmd) { |io| io.read }`, which already read all stdout into memory — output volume is unchanged, and the only addition is buffering stderr (small). The streaming `replicate` path stays on `IO.popen` and is untouched. The two `TestRunExecution` tests that stubbed `IO.popen` are rewritten to stub `Open3.capture3`.
- **Tabular commands now raise on non-zero exit at `run` level.** For `databases`/`generations`/`ltx` this is equivalent-or-better than the prior `execute`-level ERROR-row raise (same `CommandFailedException`, better reason from stderr). A broken `databases` call surfacing on the dashboard was already a `CommandFailedException`/500 path pre-change, so no new regression; `ProcessesController` behavior is unchanged on success.
- **Reason text may be verbose** (raw stderr). Acceptable — it is remediation signal; the controller prepends its own guidance (#8).
- **stderr no longer inherited to the terminal** for `run` commands (it is captured). Minor: previously stderr leaked to the console on failure; now it lands in the exception message where it belongs.
