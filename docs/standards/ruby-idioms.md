# Ruby Idioms

Judgment calls that sit on top of `standardrb`. Don't restate what the linter auto-formats — defer all formatting to it.

1. `# frozen_string_literal: true` as line 1 of every `.rb` file. `standardrb` won't add it; the gate hook catches its absence.
2. Group singleton methods under a `class << self` block, not scattered `def self.x`.
3. Expose config as reader methods wrapping `ENV["X"] || @@x || default`, paired with `mattr_writer` — not `mattr_accessor`. This lets an env var override a value set after load.
4. Accept command options as a `**argv` keyword splat and forward them downstream.
5. Build shell commands as an array for `IO.popen`/`exec(*cmd)`. Never interpolate into a string or backticks — an interpolated shell-out is a rule violation and an injection surface.
6. Every `# standard:disable <Cop>` is inline, scoped to a single statement, and justified by context.
