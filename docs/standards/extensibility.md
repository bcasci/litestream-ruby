# Extensibility, API & Versioning

1. Keep the gem version (`version.rb`) and the bundled binary version (`upstream.rb`) as independent constants with independent release cadence.
2. Add a subcommand as a public method delegating to `execute(name, argv, database)`. Guard database-requiring ones, and set `tabled_output:` explicitly (`false` for raw text, `true` for tabular).
3. The supported public surface is the `class << self` public methods plus the `mattr`/`ENV` config accessors. Everything else goes under `private` and stays refactorable.
4. Remove public API only through `Litestream.deprecator` with a target version, then a `**BREAKING**` CHANGELOG entry — one deprecation cycle before deletion. Keep the deprecation target version current.
5. Handle upstream command renames/removals by aliasing to the new method or raising `CommandNotSupportedException` with migration guidance — never a `NoMethodError`, and warn via the deprecator when a name is renamed.
6. When the config template (`config.yml.erb`) changes, track the upstream config format it targets against `Upstream::VERSION`.
7. Support the declared matrix (Ruby >= 3.0, Rails >= 7). Don't use features past that floor.
