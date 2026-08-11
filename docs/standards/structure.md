# Structure & Organization

1. Namespace every class and module under `Litestream::`. Sole sanctioned exception: `lib/puma/plugin/litestream.rb`, which must follow Puma's unnamespaced plugin convention.
2. Put core (non-Rails) logic in `lib/litestream/`, wired via `require_relative` at the bottom of `lib/litestream.rb`. Require Rails-coupled code conditionally (`if defined?(::Rails::Engine)`); require core code unconditionally.
3. One responsibility per file: `Commands` wraps the CLI, the `Litestream` module holds settings, `Upstream` holds the binary version + platform map, `Engine` does Rails wiring.
4. `upstream.rb` is the single source of truth for the binary version and platform-filename map. Reference it everywhere; never duplicate the version.
5. Mirror Rails conventions under `app/`: controllers inherit the engine `ApplicationController`, jobs live under `app/jobs/litestream/`, views under `app/views/litestream/`.
6. Rake tasks are a thin `litestream:`-namespaced surface that delegate to `Litestream::Commands`. Keep CLI logic out of the task body so it stays testable.
7. Keep generators self-contained under `lib/litestream/generators/litestream/` (generator + `templates/`) and load them lazily via `Engine.generators`.
8. Use one config scheme. Don't add a parallel settings mechanism beside the existing `mattr` + ENV-fallback readers.
