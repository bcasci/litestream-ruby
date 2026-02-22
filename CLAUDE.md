# Claude Code Configuration - litestream-ruby

## Behavioral Rules (Always Enforced)

- Do what has been asked; nothing more, nothing less
- NEVER create files unless they're absolutely necessary for achieving your goal
- ALWAYS prefer editing an existing file to creating a new one
- NEVER proactively create documentation files (*.md) or README files unless explicitly requested
- NEVER save working files, text/mds, or tests to the root folder
- Never continuously check status after spawning a swarm — wait for results
- ALWAYS read a file before editing it
- NEVER commit secrets, credentials, or .env files

## Project Overview

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

## Security Rules

- NEVER hardcode API keys, secrets, or credentials in source files
- NEVER commit .env files or any file containing secrets
- Always validate user input at system boundaries
- Always sanitize file paths to prevent directory traversal

## Concurrency: 1 MESSAGE = ALL RELATED OPERATIONS

- All operations MUST be concurrent/parallel in a single message
- Use Claude Code's Task tool for spawning agents, not just MCP
- ALWAYS batch ALL file reads/writes/edits in ONE message
- ALWAYS batch ALL Bash commands in ONE message

## Swarm Orchestration

- MUST initialize the swarm using CLI tools when starting complex tasks
- MUST spawn concurrent agents using Claude Code's Task tool
- Never use CLI tools alone for execution — Task tool agents do the actual work
- MUST call CLI tools AND Task tool in ONE message for complex work

### Project Config

- **Topology**: hierarchical-mesh
- **Max Agents**: 15
- **Memory**: hybrid
- **HNSW**: Enabled
- **Neural**: Enabled

## Swarm Configuration & Anti-Drift

- ALWAYS use hierarchical topology for coding swarms
- Keep maxAgents at 6-8 for tight coordination
- Use specialized strategy for clear role boundaries
- Use `raft` consensus for hive-mind (leader maintains authoritative state)
- Run frequent checkpoints via `post-task` hooks
- Keep shared memory namespace for all agents

```bash
npx @claude-flow/cli@latest swarm init --topology hierarchical --max-agents 8 --strategy specialized
```

## Swarm Execution Rules

- ALWAYS use `run_in_background: true` for all agent Task calls
- ALWAYS put ALL agent Task calls in ONE message for parallel execution
- After spawning, STOP — do NOT add more tool calls or check status
- Never poll TaskOutput or check swarm status — trust agents to return
- When agent results arrive, review ALL results before proceeding

## V3 CLI Commands

### Core Commands

| Command | Subcommands | Description |
|---------|-------------|-------------|
| `init` | 4 | Project initialization |
| `agent` | 8 | Agent lifecycle management |
| `swarm` | 6 | Multi-agent swarm coordination |
| `memory` | 11 | AgentDB memory with HNSW search |
| `task` | 6 | Task creation and lifecycle |
| `session` | 7 | Session state management |
| `hooks` | 17 | Self-learning hooks + 12 workers |
| `hive-mind` | 6 | Byzantine fault-tolerant consensus |

## Available Agents (60+ Types)

### Core Development
`coder`, `reviewer`, `tester`, `planner`, `researcher`

### Specialized
`security-architect`, `security-auditor`, `memory-specialist`, `performance-engineer`

### Swarm Coordination
`hierarchical-coordinator`, `mesh-coordinator`, `adaptive-coordinator`

### GitHub & Repository
`pr-manager`, `code-review-swarm`, `issue-tracker`, `release-manager`

## Memory Commands Reference

```bash
# Store (REQUIRED: --key, --value; OPTIONAL: --namespace, --ttl, --tags)
npx @claude-flow/cli@latest memory store --key "pattern-auth" --value "JWT with refresh" --namespace patterns

# Search (REQUIRED: --query; OPTIONAL: --namespace, --limit, --threshold)
npx @claude-flow/cli@latest memory search --query "authentication patterns"

# List (OPTIONAL: --namespace, --limit)
npx @claude-flow/cli@latest memory list --namespace patterns --limit 10

# Retrieve (REQUIRED: --key; OPTIONAL: --namespace)
npx @claude-flow/cli@latest memory retrieve --key "pattern-auth" --namespace patterns
```

## Quick Setup

```bash
claude mcp add claude-flow -- npx -y @claude-flow/cli@latest
npx @claude-flow/cli@latest daemon start
npx @claude-flow/cli@latest doctor --fix
```

## Claude Code vs CLI Tools

- Claude Code's Task tool handles ALL execution: agents, file ops, code generation, git
- CLI tools handle coordination via Bash: swarm init, memory, hooks, routing
- NEVER use CLI tools as a substitute for Task tool agents

## Support

- Documentation: https://github.com/ruvnet/claude-flow
- Issues: https://github.com/ruvnet/claude-flow/issues
