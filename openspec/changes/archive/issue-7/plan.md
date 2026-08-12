Status: archived

## Problem

The pinned Litestream binary is `v0.5.8`, which predates the compaction / auto-recover fixes shipped in v0.5.11–v0.5.16 (upstream `benbjohnson/litestream#1225/#1227/#1286/#1326`). Boswell production is hitting the v0.5 compaction loop that those fixes make recoverable. Bump the pinned binary to `v0.5.16`.

`Litestream::Upstream::VERSION` is the only lever — both the runtime downloader (`Commands.download_url`) and `rakelib/package.rake` build asset URLs from it; the platform filenames derive from it via `delete_prefix("v")`.

## Acceptance criteria

- [ ] `Litestream::Upstream::VERSION == "v0.5.16"`.
- [ ] All five `NATIVE_PLATFORMS` keys interpolate a filename embedding `0.5.16`, and the four distinct assets they name all exist on the v0.5.16 release (verified — see Risks). `aarch64-linux` and `arm64-linux` both map to `litestream-0.5.16-linux-arm64.tar.gz`.
- [ ] `Commands.download_url` builds the correct `v0.5.16` asset URL for all five `NATIVE_PLATFORMS` keys, not just the host platform.
- [ ] Existing tests still pass (the rake-task "missing assertions" warnings are expected and permitted).

## Test list

- Criterion 1 — add a one-line literal assertion: `assert_equal "v0.5.16", Litestream::Upstream::VERSION`. The existing `TestDownloadUrl` derives its expected URL *from* `Upstream::VERSION`, so it passes for any value and cannot catch a wrong constant — do not rely on it for criterion 1.
- Criteria 2 & 3 — add a guard test that iterates all five `NATIVE_PLATFORMS` keys, stubs `Commands.platform`, and asserts `download_url` equals the expected `v0.5.16` URL for each. Write each expected URL as a **hard-coded literal string** containing `0.5.16` (e.g. `https://github.com/benbjohnson/litestream/releases/download/v0.5.16/litestream-0.5.16-linux-arm64.tar.gz`), NOT interpolated from `Upstream::VERSION` — otherwise the assertion is tautological and pins nothing. The two `linux-arm64` keys intentionally assert the same filename. Place it in a **new test class that does not inherit `TestDownload`** — that class's `setup`/`teardown` `rm_rf`s `Commands::DEFAULT_DIR/<platform>`, and `download_url` has no filesystem side effect, so it needs no such setup. This keeps the test offline and avoids the shared-dir deletion (`docs/standards/testing.md` #3, #7).
- Criterion 4 — `rake test` passes.

## Approach + files

- `lib/litestream/upstream.rb` — set `VERSION = "v0.5.16"` (one line). Filenames derive from it; nothing else in the map changes.
- `test/litestream/test_download.rb` — add, in a new class that does not inherit `TestDownload`: (a) a literal `assert_equal "v0.5.16", Litestream::Upstream::VERSION`, and (b) the five-key `download_url` guard test with hard-coded literal expected URLs.

No other code changes; `commands.rb` and `package.rake` already read `Upstream::VERSION`.

## Verification (gated, not a unit test)

- Issue #7 acceptance item 2 — actual fetch of the v0.5.16 binary on `linux-x86_64`, `linux-arm64`, `darwin-x86_64`, `darwin-arm64`. Network is stubbed in tests (`docs/standards/testing.md`), so this is a manual/CI check performed at release, tracked here as a **required gated item** — not downgraded to the offline URL-string proxy.

## Out of scope / gated

- Gem version bump (`lib/litestream/version.rb`), a CHANGELOG entry, the `git tag`, and the `bin/release` publish of the native-platform gems. Issue #7 lists the pushed tag + published gems as acceptance, and Boswell `#711` is blocked on the tag landing — so a release action **is required after this merges**, done as the authorized release step, not in this change.

## Risks

- Asset availability — verified: the four distinct assets `litestream-0.5.16-{linux-x86_64,linux-arm64,darwin-x86_64,darwin-arm64}.tar.gz` exist on the v0.5.16 release, matching what the five `NATIVE_PLATFORMS` keys interpolate. `aarch64-linux` and `arm64-linux` share the single `linux-arm64` asset, so the guard test's duplicate expectation is intentional, not a copy error. Closed.
- No gem API change — the bump is binary-only; the gem-vs-upstream two-version scheme keeps gem code stable. The behavior change is the upstream binary's compaction/auto-recover fixes (the intent).
- Runtime download of the new binary is not unit-tested (network is stubbed) — covered by the gated Verification step above.
