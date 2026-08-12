Status: archived

## Problem

Six gaps surfaced while authoring `docs/standards/`; `standardrb` is clean, so each is a code-vs-standard gap fixed by changing code, not by a lint exception or a standards edit. Five are documented-standard violations (items 1–5); item 6 is an optional readability note with no governing rule.

Two corrections to the issue's premises, verified against the tree:
- **Item 1**: `lib/litestream/upstream.rb` *already* has `# frozen_string_literal: true` (line 1). Only `lib/litestream/commands.rb` is missing it. Scope item 1 to `commands.rb` alone.
- **Item 2**: the only *interpolated* (injection-surface) shell-out is `` `#{Litestream.systemctl_command}` `` (`systemctl_command` is user-settable via `mattr`). The others in scope — `` `which systemctl` ``, `` `ps -ax | grep litestream | grep replicate` ``, `` `ps -o "state,lstart" #{pid}` `` (`lib/litestream.rb`) and `` `#{cmd.join(" ")}` `` (`Commands.run`) — are backtick shell-outs the standard also says to move to array form. All are converted for full ruby-idioms rule 5 conformance.

## Acceptance criteria

**Item 1 — frozen string literal (ruby-idioms rule 1)**
- [ ] `lib/litestream/commands.rb` begins with `# frozen_string_literal: true` followed by a blank line, above the existing `require_relative "upstream"`.

**Item 2 — array shell-outs, no interpolation (ruby-idioms rule 5)**
- [ ] `Commands.run` executes the command via `IO.popen(cmd, ...)` on the existing `cmd` **array**, not `` `#{cmd.join(" ")}` ``; its parsed/tabular output is unchanged.
- [ ] `Litestream#systemctl_info` runs the user-set `systemctl_command` without a shell: the string is split with `Shellwords.split` and executed as an argument array via `IO.popen`, so shell metacharacters in `systemctl_command` are not interpreted. `systemctl` presence is detected by **empty stdout** from `capture("which", "systemctl")` — preserving the current `.empty?` semantics, not switching to `$?`.
- [ ] `Litestream#process_info` finds the litestream replicate process by running `ps` as an argument array and filtering the lines in Ruby for `litestream` + `replicate` (no shell pipe), and runs `ps -o state,lstart <pid>` as an argument array (pid passed as a separate arg, not interpolated).
- [ ] No `` ` `` backtick shell-out remains in `lib/litestream.rb` or `lib/litestream/commands.rb` (backticks inside string/heredoc *messages* are not shell-outs and are allowed).
- [ ] `Litestream.replicate_process` returns the same shape as before for the systemd and ps cases (`:pid`, `:status`, `:started`).

**Item 3 — nil-guarded `verify!` ensure (error-handling rule 6)**
- [ ] When `SQLite3::Database.new(database_path)` raises, `Litestream.verify!` propagates that original error — the `ensure` block does not raise `NoMethodError` by calling `execute`/`close` on `nil`, nor `Dir.glob` on a nil `backup_path`.
- [ ] The success path of `verify!` still deletes the sentinel row, closes the database, and removes the backup file(s).

**Item 4 — `RestorationsController#create` rescue (error-handling rule 7)**
- [ ] When `Litestream::Commands.restore` raises `DatabaseRequiredException` or `CommandFailedException`, `create` rescues it and redirects to the engine root (no unhandled 500), setting an `alert` flash that both echoes the exception message and gives recovery guidance (a fixed remediation clause: verify the database path and Litestream configuration, then retry) — so the message tells the user how to recover, per rule 7, not just what broke.
- [ ] On success the existing redirect with the "Restored to …" notice is unchanged.

**Item 5 — remove the completed `Litestream.configure` deprecation (extensibility rule 4) — DECIDED: full removal**
- [ ] `Litestream.configure` is removed (the `def self.configure` at `lib/litestream.rb:20`); `Litestream.respond_to?(:configure)` is false.
- [ ] The now-dead `Configuration` class and the `|| configuration.replica_*` fallbacks in `replica_bucket`/`replica_key_id`/`replica_access_key` are removed (they existed only to serve `configure`); those readers now resolve from `ENV` → `@@x` only.
- [ ] `Litestream.deprecator` is **kept** (registered by `engine.rb` as `app.deprecators[:litestream]` and required by extensibility rules 4–5 for future deprecations).
- [ ] The one README example using `Litestream.configure` (the MinIO/dev section, ~line 506) is updated to the `Rails.application.configure { config.litestream.replica_bucket = … }` form.
- [ ] A `**BREAKING**` entry is added to `CHANGELOG.md` under `[Unreleased]` noting `Litestream.configure` removal and the replacement.

**Item 6 — `Litestream.databases` readability (no rule; opted in)**
- [ ] `Litestream.databases` builds its result with `map` (stating intent) rather than `.each` + in-place hash mutation, returning the same array-of-hashes shape (`path` rewritten to `[ROOT]`, sliced `generations`). Existing dashboard behavior unchanged.

**Global**
- [ ] `rake test` and `standardrb` are both green.

## Test list

- **Item 1** — verification is the `standardrb` run + the `.claude/hooks/standardrb-gate.sh` gate (no meaningful unit test for a magic comment); asserting a frozen literal would test Ruby, not our code. Listed as a non-unit gated check.
- **Item 2 / `Commands.run` tabular** — stub `IO.popen` to assert `run` calls it with the `cmd` **array** (not a joined string) and parses the returned tabular text into the expected array-of-hashes. (`test/litestream/test_commands.rb`; existing command tests stub `:run` and are unaffected.)
- **Item 2 / `Commands.run` raw** — a test for the `tabled_output: false` branch: stub `IO.popen` and assert `run` returns the raw `chomp`ed stdout string (the path `restore` uses), confirming the `IO.popen` refactor covers both output modes.
- **Item 2 / systemd** — rewrite `test_replicate_process_systemd` and `_custom_command` to stub the new array executor (the private `capture` helper) instead of `Litestream.stub :\``; assert the parsed `:pid`/`:status`/`:started`. Add one test that a `systemctl_command` containing a shell metacharacter (e.g. `"systemctl status x; touch pwned"`) is passed as split argv (the executor receives the token array `["systemctl","status","x;","touch","pwned"]`) and is never shell-interpreted.
- **Item 2 / systemctl absent** — stub `capture("which","systemctl")` to return `""`; assert `systemctl_info` returns early (nil) so `replicate_process` falls through to `process_info` — pinning the preserved empty-stdout detection semantics.
- **Item 2 / ps** — rewrite `test_replicate_process_ps` to stub the array executor for `["ps","-ax"]` (returns the process list) and `["ps","-o","state,lstart",<pid>]`; assert `:pid`/`:status`/`:started`. Add a test that when no line matches `litestream`+`replicate`, `process_info` yields the empty result and `replicate_process` returns `{}`.
- **Item 3 / failure** — stub `SQLite3::Database.new` to raise; assert `verify!` re-raises that error class (not `NoMethodError`), proving the `ensure` guards hold. (`test/test_litestream.rb`.)
- **Item 3 / success** — create a real temp SQLite db under `tmp`, then stub `Litestream::Commands.restore` with a proc that captures its `-o` keyword argument and `FileUtils.cp`s the source db to that path. This works because `verify!` inserts the sentinel *before* calling `restore`, so copying the live source db yields a backup already containing the sentinel row — the stub needs neither the internal `sentinel` uuid nor the generated `backup_path` in advance. Call `verify!(db, replication_sleep: 0)`; assert it returns `true` and that the backup file(s) are deleted afterward — proving the guarded `ensure` still performs sentinel-delete, close, and backup cleanup. Confine all files to a created/removed `tmp` path (testing.md #7).
- **Item 4** — via the mounted route (`ActionDispatch::IntegrationTest`), `POST litestream.restorations_url` with `Litestream::Commands.stub :restore` raising `CommandFailedException`; assert a redirect to the engine root (3xx, not 500) **and** that the `alert` flash contains both the exception message and the fixed recovery clause (assert the flash text, not just its presence — testing.md #5). A second test stubs `restore` raising `DatabaseRequiredException` with the same expectation. (`test/controllers/test_restorations_controller.rb`, new.)
- **Item 5** — assert `Litestream.respond_to?(:configure)` is `false`; assert `Litestream.deprecator` still responds (kept); assert `defined?(Litestream::Configuration)` is nil (class removed); assert a config reader still works via the surviving path — e.g. set `Litestream.replica_bucket = "x"` and `assert_equal "x", Litestream.replica_bucket`, and that `ENV["LITESTREAM_REPLICA_BUCKET"]` still overrides. (`test/test_litestream.rb`; reset mutated globals in teardown per testing.md #6.)
- **Item 6** — assert `Litestream.databases` returns the expected array-of-hashes (path rewritten to `[ROOT]`, `generations` sliced to the whitelisted keys) given stubbed `Commands.databases`/`Commands.generations` — a behavior test that survives the `.each`→`map` refactor unchanged. (`test/test_litestream.rb`.)
- **Global** — `rake test` passes (task "missing assertions" warnings are expected).

## Approach + files

- **Item 1** — `lib/litestream/commands.rb`: prepend the magic comment + blank line.
- **Item 2** — `lib/litestream/commands.rb`: `Commands.run` → `IO.popen(cmd) { |io| io.read }.chomp` (cmd already an array). `lib/litestream.rb`: add a private `capture(*command)` helper wrapping `IO.popen(command, &:read)` (sets `$?` on close for the exit-status checks). Rewrite `systemctl_info` to detect systemctl via `capture("which", "systemctl")` and run `capture(*Shellwords.split(Litestream.systemctl_command))`; rewrite `process_info` to `capture("ps", "-ax")`, filter lines in Ruby, then `capture("ps", "-o", "state,lstart", pid)`. Preserve exit-status early-returns (`$?`), the systemd `Main PID:`/`Active:` parsing, and the ps `state`→status mapping. `require "shellwords"` at the top of `lib/litestream.rb`.
- **Item 3** — `lib/litestream.rb` `verify!`: initialize `database = nil` / `backup_path = nil` before the body; in `ensure` guard `database&.execute(...)` (and only when `defined?(sentinel) && sentinel`), `database&.close`, and `Dir.glob(backup_path + "*")` only when `backup_path`.
- **Item 4** — `app/controllers/litestream/restorations_controller.rb`: wrap the `restore` call; `rescue Litestream::Commands::DatabaseRequiredException, Litestream::Commands::CommandFailedException => e` → `redirect_to root_path, alert: "Restore failed: #{e.message} — verify the database path and your Litestream configuration, then retry."`. `root_path` here is the engine root (`processes#show`), same helper the success redirect already uses. Keep the success redirect.
- **Item 5** — `lib/litestream.rb`: delete `self.configure` (lines 20–27), the `Configuration` class (lines 29–34), and the `|| configuration.replica_*` fallbacks in the three reader methods; keep `deprecator`. `README.md`: rewrite the MinIO example (~line 506) to `Rails.application.configure { config.litestream.replica_bucket = … }`. `CHANGELOG.md`: add a `**BREAKING**` bullet under `[Unreleased]`.
- **Item 6** — `lib/litestream.rb` `databases`: replace the `.each` + in-place mutation with `Commands.databases.map { |db| … }` returning the transformed hashes; identical output shape.

Tests: `test/litestream/test_commands.rb`, `test/test_litestream.rb`, `test/controllers/test_restorations_controller.rb` (new), per the Test list. All executors stubbed — no real `ps`/`systemctl`/SQLite process (testing.md #3, #7).

## Out of scope / gated

- **Gate decisions (resolved):** Item 5 → **full removal** of `Litestream.configure` + its dead `Configuration` class/fallbacks (keep `deprecator`, update README, `**BREAKING**` CHANGELOG). Item 6 → **included** (`.each`→`map`).
- Not deprecating the `Configuration`-independent config surface (`mattr` writers, ENV readers, `config.litestream.*`) — that path stays; only the `configure` shim and its private backing are removed.
- No behavior change to `replicate_process`'s output contract, the dashboard, or any rake task.

## Risks

- **Shell-out refactor changes execution mechanics (item 2).** Moving off backticks to argv `IO.popen` removes the shell, so `systemctl_command` values that *relied* on shell features (pipes, `;`, env expansion) would break — but that is the injection surface the standard targets, and `systemctl_command` is meant to be a plain command. The systemd/ps parsing is preserved; the existing tests are rewritten to stub the new executor, so a behavior regression would surface there. The ps early-return-on-no-match is reproduced by checking the filtered result.
- **`$?` after `IO.popen`.** The exit-status checks in `systemctl_info`/`process_info` depend on `$?` being set; `IO.popen(cmd, &:read)` sets it when the stream closes. The rewritten tests assert the no-match/early-return paths so this is covered.
- **Item 4 flash key.** Using `alert:` assumes the host layout renders it; the engine's own views drive the dashboard, and the assertion targets the redirect + flash, not host rendering. Low risk.
- **Item 5 breaking removal.** `Litestream.configure` (public) disappears, along with the `Configuration` class and the `|| configuration.replica_*` reader fallbacks. Verified: nothing in `lib/`, `app/`, `test/`, or the dummy app calls `configure` or reads `configuration` except the one README example (updated here); the readers keep their `ENV → @@x` resolution and the `config.litestream.*` engine path is untouched. Mitigated by the long-complete deprecation cycle and the `**BREAKING**` CHANGELOG entry.
