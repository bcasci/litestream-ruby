Status: archived

## Problem

`lib/puma/plugin/litestream.rb` registers its lifecycle hooks with `on_booted`, `on_restart` and `on_stopped`. Puma 7 renamed these to `after_booted`, `before_restart` and `after_stopped`, and kept the old names as deprecated aliases that call `Puma.deprecate_method_change` (`puma-8.0.2/lib/puma/events.rb:45-58`).

On Puma 7 and 8 every boot logs three lines:

```
Use 'after_booted', 'on_booted' is deprecated and will be removed in v8
Use 'after_stopped', 'on_stopped' is deprecated and will be removed in v8
Use 'before_restart', 'on_restart' is deprecated and will be removed in v8
```

The warning names v8, but the aliases are still present in Puma 8.0.2, so the real removal version is unknown. When Puma removes them the plugin raises `NoMethodError` during `start` and no Litestream process is ever started.

This is not a defect on any released Puma. It is future compatibility plus log noise. It was left out of [#15](https://github.com/bcasci/litestream-ruby/pull/15), which was scoped to the pid-tracking defects in #14.

A plain rename does not work. Checked against the Puma source:

| Puma | `after_booted` present |
|---|---|
| 6.4.2 | no |
| 6.6.0 | no |
| 7.0.0 | yes |
| 8.0.2 | yes |

The gem supports Rails >= 7 and declares no Puma version constraint, so Puma 6 is in range. Renaming outright would break Puma 6 users with the same `NoMethodError` in the other direction.

## Acceptance criteria

- [ ] On a Puma whose events object responds to `after_booted`, `before_restart` and `after_stopped`, the plugin registers all three hooks under those names and never calls `on_booted`, `on_restart` or `on_stopped`.
- [ ] On a Puma whose events object responds only to `on_booted`, `on_restart` and `on_stopped`, the plugin registers all three hooks under those names.
- [ ] Hook behaviour is unchanged in both cases: booting sets `@litestream_pid` and clears the deliberate-stop flag; stopping and restarting both run `stop_litestream`.
- [ ] Booting a real Puma logs no deprecation warning from this plugin.
- [ ] The name chosen per event is decided by the events object, not by a Puma version check, so a Puma that carries only one of the two sets works either way.
- [ ] `rake test` and `standardrb` are both green.

## Test list

`test/test_puma_plugin.rb` already drives the plugin through a fake launcher. Split the current `FakeEvents` into two, one per naming scheme, and let `FakeLauncher` take which to use. `ModernEvents` becomes the default so every existing test exercises the path current Puma takes.

- **Criteria 1 and 3 (modern names)** — start the plugin against `ModernEvents` (defines only `after_booted`, `before_restart`, `after_stopped`); assert all three blocks were captured, then fire each and assert the existing behaviour (pid recorded on boot, `stop_litestream` run on stop and on restart). The existing test classes cover the behaviour once `ModernEvents` is the default, so this adds only the registration assertion.
- **Criterion 2 (legacy names)** — start the plugin against `LegacyEvents` (defines only `on_booted`, `on_restart`, `on_stopped`); assert all three blocks were captured.
- **Criterion 3 (legacy names, behaviour)** — against `LegacyEvents`, fire the booted block and assert `litestream_pid` is set, then fire the restart block and assert Litestream is signalled. Proves the fallback registers working blocks, not just any block.
- **Criterion 5** — against an events object that responds to `after_booted` but not `before_restart` (a mixed shape), assert booting uses the new name and restart falls back to `on_restart`. Guards against a version check being reintroduced.
- **Criterion 4** — in `test/integration/test_puma_plugin_restart.rb`, assert the captured Puma log contains no `is deprecated` line. Holds on Puma 6 (no warning is emitted) and on Puma 7 and 8 (no longer emitted). The test already captures Puma's output to a log file for its failure messages.

## Approach + files

**`lib/puma/plugin/litestream.rb`**

Add a private helper that picks the name the events object actually has, and route all three registrations through it:

```ruby
# Puma 7 renamed the lifecycle events and kept the old names as deprecated
# aliases. Puma 6, which this gem still supports, has only the old names, so
# ask the events object rather than checking a Puma version.
def register_event(events, name, legacy_name, &block)
  name = legacy_name unless events.respond_to?(name)
  events.public_send(name, &block)
end
```

`start` becomes:

```ruby
register_event(launcher.events, :after_booted, :on_booted) do
  @stopping = false
  @litestream_pid = Litestream::Commands.replicate(async: true)
end

register_event(launcher.events, :after_stopped, :on_stopped) { stop_litestream }
register_event(launcher.events, :before_restart, :on_restart) { stop_litestream }
```

Nothing else in the plugin changes. `in_background` keeps its place in `start`, per #14.

**`test/test_puma_plugin.rb`** — replace `FakeEvents` with `ModernEvents` and `LegacyEvents`, give `FakeLauncher` an events-class argument defaulting to `ModernEvents`, and add a `TestEventRegistration` class for the criteria above.

**`test/integration/test_puma_plugin_restart.rb`** — add the no-deprecation-warning assertion.

**`CHANGELOG.md`** — entry under `## [Unreleased]`.

## Out of scope

- Declaring a Puma version constraint in the gemspec. The plugin is optional; a hard dependency would force Puma on users who do not run it.
- Dropping Puma 6 support. That is a separate decision with its own support-matrix consequences.
