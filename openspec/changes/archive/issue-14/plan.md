Status: implemented

## Problem

The Puma plugin never stops the Litestream process it starts. Litestream processes accumulate one per Puma restart. They contend for SQLite's checkpointer lock, so no truncate checkpoint completes and the WAL grows without bound. Reported in [#14](https://github.com/bcasci/litestream-ruby/issues/14) from a production Fly.io machine on v0.16.0: three `litestream replicate` processes matching three Puma restarts, a 3.0G WAL against a 232K database, and `pragma wal_checkpoint(PASSIVE)` returning `1|-1|-1`.

Two independent defects produce this.

**Defect 1 — the tracked pid is not the Litestream process.** `lib/puma/plugin/litestream.rb:11` forks child A and records A as `@litestream_pid`. Inside A, `run_replicate` (`lib/litestream/commands.rb:232`) forks again: `exec(*cmd) if fork.nil?`. Child B execs the binary; in A `fork` returns B's pid, so `exec` is skipped, `replicate` returns, the block ends, and A exits. Nothing holds B's pid. Reproduced locally with a stub binary:

```
recorded @litestream_pid=69378
  PID  PPID STAT COMMAND
69379     1 S    sleep 300        # the real process, orphaned to PPID 1
```

`stop_litestream` then calls `Process.waitpid(litestream_pid, WNOHANG)` first. A is a zombie, so that call **succeeds** and reaps it; `Process.kill(:INT, litestream_pid)` on the next line runs against a just-reaped pid. B is never signalled. `on_stopped` and `on_restart` are both no-ops against the real process. The reap-before-kill order is itself a hazard: a reaped pid can be recycled, and the plugin would signal an unrelated process.

**Defect 2 — the liveness monitor never runs.** `in_background { monitor_litestream }` is called *inside* the `on_booted` block. `Puma::Plugin#in_background` only appends the block to `Puma::Plugins`' `@background` array, and `Plugins.fire_background` iterates that array exactly once, **before** the booted event fires (puma 8.0.2: `cluster.rb:428` vs `fire_after_booted!` at 512/529; `single.rb:46` vs 61). The block is registered after the iteration and never called. No thread, no `litestream_dead?` check, no SIGINT to Puma. This is why the production Puma stayed up while its Litestream child was long gone.

`monitor_puma` is dead in the same way: it runs in a thread inside child A, which exits as soon as `replicate` returns.

Constraint on any fix: Puma's master reaps **any** child, not only its workers — `wait_workers` loops on `Process.wait2(-1, Process::WNOHANG)` (`cluster.rb:566-574`), deliberately, so Puma can act as PID 1's reaper in containers. So `waitpid` may raise `Errno::ECHILD` because Puma got there first. Liveness and stopping must not depend on `waitpid` succeeding.

The non-async path is not affected: `run_replicate(cmd, async: false)` uses `IO.popen(cmd, err: [:child, :out])` with a block, which spawns one child and reaps it. `rake litestream:replicate` takes that path (`async` defaults to `false`). No other caller passes `async: true`.

## Acceptance criteria

- [ ] `Litestream::Commands.replicate(async: true)` returns the pid of the process that runs the Litestream binary. Exactly one child process is created, not two.
- [ ] `Litestream::Commands.replicate(async: false)` is unchanged: it runs in-process via `IO.popen`, streams output to stdout, blocks until the child exits, and returns `nil`.
- [ ] The Puma plugin records that returned pid as `@litestream_pid`.
- [ ] `stop_litestream` checks liveness with `Process.kill(0, pid)`, sends `SIGINT`, and only then reaps. It never reaps before signalling.
- [ ] `stop_litestream` survives Puma's master having already reaped the child: `Errno::ECHILD` and `Errno::ESRCH` do not raise out of it, and do not cause a signal to be sent to a reaped pid.
- [ ] `stop_litestream` is a no-op when no Litestream process was started (`@litestream_pid` is `nil`).
- [ ] `in_background { monitor_litestream }` is registered in `start`, outside the `on_booted` block, so Puma's `fire_background` picks it up.
- [ ] `monitor_litestream` tolerates `@litestream_pid` still being `nil` (it is registered before `on_booted` sets it) and does not signal Puma in that window.
- [ ] `monitor_litestream` reaps the child before testing liveness, so a zombie is not read as alive.
- [ ] `monitor_litestream` does not SIGINT Puma when the plugin stopped Litestream deliberately (`on_stopped` / `on_restart`).
- [ ] `monitor_puma`, `puma_dead?`, `litestream_dead?` and `attr_reader :puma_pid` are removed. They cannot work in the single-fork shape and have never worked in the shipped shape.
- [ ] **Regression:** driving the plugin through boot → restart → boot leaves exactly one Litestream process running. This is the criterion the bug survived three production restarts by not having.
- [ ] `rake test` and `standardrb` are both green.

## Test list

New file `test/test_puma_plugin.rb` (`Minitest::Test`). The plugin registers itself under the name `litestream`, so the class under test is `Puma::Plugins.find("litestream")`. A fake launcher supplies `log_writer` and an `events` double capturing the `on_booted` / `on_stopped` / `on_restart` blocks, plus a captured `in_background` block, so each hook can be fired on demand.

Unit tests (no real process; `Litestream::Commands.replicate` stubbed):

- **Criterion 3** — fire `on_booted`; assert the plugin's `litestream_pid` equals the pid the stubbed `replicate` returned, and that `replicate` was called with `async: true` (`Minitest::Mock` + `.verify`).
- **Criterion 4** — stub `Process.kill`/`Process.waitpid` to record call order; fire `on_stopped`; assert the recorded order is `kill(0, pid)`, `kill(:INT, pid)`, `waitpid(pid)`. Assert no `waitpid` precedes the `:INT`.
- **Criterion 5** — stub `Process.kill(0, …)` to raise `Errno::ESRCH`; fire `on_stopped`; assert no exception escapes and `Process.kill(:INT, …)` is never called.
- **Criterion 5** — stub `Process.waitpid` to raise `Errno::ECHILD` after a successful signal; fire `on_stopped`; assert no exception escapes.
- **Criterion 6** — call `start` but never fire `on_booted`; fire `on_stopped`; assert no exception and no `Process.kill` at all.
- **Criterion 7** — call `start`; assert a background block was registered during `start` itself, before `on_booted` has been fired. (Directly asserts the puma ordering defect.)
- **Criterion 8** — run one pass of the monitor block with `litestream_pid` still `nil`; assert no signal is sent to Puma.
- **Criterion 9** — stub the pid as a zombie (first `kill(0)` succeeds, `waitpid` reaps, second `kill(0)` raises `Errno::ESRCH`); run one monitor pass; assert Litestream is reported dead and Puma is signalled.
- **Criterion 10** — fire `on_stopped`, then run one monitor pass; assert Puma is not signalled.

Command-layer tests in `test/litestream/test_commands.rb`:

- **Criterion 1** — stub `Process.spawn` to return a known pid; assert `Commands.replicate(async: true)` returns that pid and that `Process.spawn` received the argv array (`Minitest::Mock` + `.verify`), with `IO.popen` never called.
- **Criterion 2** — stub `IO.popen`; assert `Commands.replicate(async: false)` takes the popen path and returns `nil`, and that `Process.spawn` is never called.
- **Criterion 1** — stub `Process.spawn` to raise `Errno::ENOENT`; assert `replicate(async: true)` raises `CommandFailedException` (the existing `rescue` in `replicate` still wraps it).

Regression test, new file `test/integration/test_puma_plugin_restart.rb` (`ActiveSupport::TestCase`, `use_transactional_tests = false`):

- **Criterion 11** — boot a real Puma. This follows how puma tests `tmp_restart` (`test/test_plugin.rb` boots a server with `cli_server`) and how rails/solid_queue tests this same plugin (`test/integration/puma/plugin_testing.rb` boots `bundle exec puma -C config/puma_<mode>.rb` and restarts it with `SIGUSR2`). The unit tests above call the lifecycle blocks directly, so they cannot see *when* Puma calls them, and defect 2 is exactly a question of when.
  - Write a stub executable into a test-owned tmp directory: a shell script that `exec`s `ruby --disable-gems -e 'trap("INT") { exit }; sleep' -- <sentinel> "$@"`, so it is one process, carries a unique sentinel on its command line, starts without loading bundler, and exits quietly on SIGINT.
  - `Process.spawn` `bundle exec puma -C config/puma_litestream.rb config.ru` from `test/dummy`, with `LITESTREAM_INSTALL_DIR` pointing at the stub directory and output redirected to a log file in the tmp directory.
  - Wait for the stub process to appear in `ps -ax -o pid=,command=`, filtered to the sentinel. Record its pid.
  - `Process.kill(:USR2, puma_pid)` to trigger a hot restart. Puma fires `before_restart` (aliased from `on_restart`) immediately before `Kernel.exec` in `Launcher#restart!`, so the plugin's stop runs inside a real restart.
  - Wait for exactly one stub process with a different pid, then assert the surviving set is exactly that one pid. Under the defect the wait times out and the failure message names both pids.
  - Teardown SIGTERMs Puma, kills any surviving stub, and removes the tmp directory.
  - **Deviation from `docs/standards/testing.md` #3** (stub every `fork`): this test starts real processes, and that is the point. The defect was in the process table, not in the plugin's bookkeeping; a mocked spawn proves only the bookkeeping, which is the thing that was wrong. It never runs the real Litestream binary, touches no network and no service, and confines filesystem writes to a tmp path it creates and removes (standard #7).

New support file `test/dummy/config/puma_litestream.rb`: a minimal Puma config (`threads 1, 1`, port/environment/pidfile from ENV) that loads `plugin :litestream`. The existing `test/dummy/config/puma.rb` is left alone.

## Approach + files

**`lib/litestream/commands.rb`**

Replace the double fork with `Process.spawn`, which returns the child's pid directly and does not copy the Puma master's heap. `Process.spawn` with an argv array runs no shell (ruby-idioms 5), and raises `Errno::ENOENT` in the caller when the binary is missing, which `replicate`'s existing `rescue` wraps in `CommandFailedException`.

```ruby
# Returns the pid of the process running the litestream binary when async, so the
# caller can signal the real replication process; nil when run in-process.
def run_replicate(cmd, async:)
  return Process.spawn(*cmd) if async

  # When running in-process, we capture output continuously and write to stdout.
  IO.popen(cmd, err: [:child, :out]) do |io|
    io.each_line { |line| puts line }
  end

  nil
end
```

Update the `replicate` comment above it to say it returns a pid when async.

**`lib/puma/plugin/litestream.rb`**

- Register `in_background { monitor_litestream }` in `start`, with a comment naming the puma ordering that makes the old placement dead.
- Set `@litestream_pid = Litestream::Commands.replicate(async: true)` in `on_booted`.
- Replace `stop_litestream` with: return unless `litestream_running?`; set the deliberate-stop flag; log; `Process.kill(:INT, pid)`; then reap.
- Replace `litestream_dead?` with `litestream_running?` using `Process.kill(0, pid)` (`Errno::ESRCH` → false, `Errno::EPERM` → true), and a `reap_litestream` helper wrapping `Process.waitpid(pid, Process::WNOHANG)` with `Errno::ECHILD` / `Errno::ESRCH` rescued to `nil`.
- Inline the monitor loop (the generic `monitor(process_dead, message)` helper had one remaining caller): sleep, break on the deliberate-stop flag, skip while `litestream_pid` is `nil`, reap, then test liveness.
- Delete `monitor_puma`, `puma_dead?`, `@puma_pid` and `attr_reader :puma_pid`.

**`litestream.gemspec`** — add `spec.add_development_dependency "puma"`. Puma was not in the bundle at all, which is why `lib/puma/plugin/litestream.rb` has never had a test.

**`CHANGELOG.md`** — entry under `## [Unreleased]` describing both defects and referencing #14. Note the removal of `puma_pid` / `monitor_puma`: it is a Puma plugin internal, not gem public API, so it does not go through `Litestream.deprecator`.

## Out of scope

- A SIGKILLed Puma still orphans the Litestream process. Nothing in-process can prevent that; it needs a supervisor process or a process-group kill from outside. Not part of this fix.
- Cleaning up Litestream processes already orphaned on a running production machine. That is an operational step, not a code change.
- Puma 8 deprecates `on_booted`, `on_restart` and `on_stopped` in favour of `after_booted`, `before_restart` and `after_stopped`, and warns that it will remove the old names. The plugin keeps the old names here, because the new ones do not exist on the Puma versions this gem still supports and the gem declares no Puma version constraint. Tracked separately.
