# Testing

Minitest, heavy stubbing, one dummy Rails host. No test touches a real binary, service, or network.

1. Name test files `test_*.rb` mirroring the subject's path (`lib/litestream/commands.rb` → `test/litestream/test_commands.rb`).
2. Pick the base class by layer and stay consistent for equivalent units: `ActionDispatch::IntegrationTest` (controllers), `Rails::Generators::TestCase` (generators), `ActiveSupport::TestCase` / `Minitest::Test` otherwise.
3. Stub every binary, `fork`, backtick, `systemctl`, `ps`, and `URI.open` call — no real process, service, or network.
4. Run against `test/dummy`; reach the engine through its mounted routes (`litestream.process_url`).
5. Assert the contract — exact command shape and argv, or `Minitest::Mock` + `.verify` for delegation. Not a smoke run.
6. Reset all mutated global state (`Litestream.*=`, `ENV`, `ARGV`, download dirs) in `setup`/`teardown` so tests stay order-independent.
7. Confine filesystem side effects to a `tmp` path you create and remove. Never write to or delete a shared/real dir like `Commands::DEFAULT_DIR`.
8. `assert_equal expected, actual` — expected first, so failure diffs read correctly.
9. One behavior per test.
