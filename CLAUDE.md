# litestream-ruby

Ruby gem that integrates [Litestream](https://litestream.io) (SQLite replication) with Rails applications.
Bundles the Litestream binary for multiple platforms and provides a Rails engine with a dashboard.

## Project Structure

- `lib/litestream/` - Core gem code (commands, upstream binary config, engine, generators)
- `lib/tasks/` - Rake task definitions
- `lib/puma/plugin/` - Puma plugin for automatic replication
- `app/` - Rails engine (controllers, views, jobs)
- `config/` - Engine routes
- `test/` - Minitest test suite
- `rakelib/` - Native gem packaging tasks
- `exe/` - Ruby wrapper script for the binary

## Build & Test

```bash
# Run tests
ASDF_RUBY_VERSION=3.3.8 bundle exec rake test

# Run linter
ASDF_RUBY_VERSION=3.3.8 bundle exec standardrb

# Run both (default rake task)
ASDF_RUBY_VERSION=3.3.8 bundle exec rake

# Auto-fix lint issues
ASDF_RUBY_VERSION=3.3.8 bundle exec standardrb --fix
```

- ALWAYS run tests after making code changes
- ALWAYS run the linter before committing
- Ruby version: 3.3.8 (set via `.tool-versions`)
- Test framework: Minitest
- Linter: Standard Ruby

## Key Architecture

- **Upstream binary**: Version defined in `lib/litestream/upstream.rb` (currently v0.5.8)
- **Commands**: `lib/litestream/commands.rb` wraps Litestream CLI (replicate, restore, databases, generations, ltx)
- **Config template**: `lib/litestream/generators/litestream/templates/config.yml.erb` (v0.5.x format: singular `replica`)
- **Dashboard**: Rails engine mounted at `/litestream/` showing process status and database info
- **Puma plugin**: Forks Litestream process alongside Puma for automatic replication

## Dependencies

- Ruby >= 3.0.0
- Rails >= 7.0
- sqlite3 gem
- Minitest, Standard Ruby, rubyzip (dev)

## Gem Versioning

- Gem version: `lib/litestream/version.rb`
- Upstream Litestream version: `lib/litestream/upstream.rb`
- These are independent: gem version tracks gem changes, upstream version tracks bundled binary
