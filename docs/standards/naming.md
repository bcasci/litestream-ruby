# Naming

Name things what they are. A name that no longer describes its subject is a bug.

1. Custom exceptions are named `<Condition>Exception`. (Their definition and the `# raised when …` comment: see [error handling](error-handling.md).)
2. Methods that raise on failure or mutate state end in `!` (e.g. `verify!`); predicate methods end in `?`.
3. Constants are `SCREAMING_SNAKE_CASE` named for their content (`NATIVE_PLATFORMS`, `DEFAULT_DIR`).
4. Prefix every gem-owned environment variable with `LITESTREAM_`.
5. One concept, one word — the same value gets the same name everywhere (don't call it `db` in one place and `db_hash` in another).
6. A file's path is the snake_case of the constant it defines (`verification_job.rb` → `VerificationJob`).
7. Controllers are named for the plural resource; actions are named for the HTTP verb (RESTful).
8. Don't keep a name that lies. When a command no longer does what its name says, deprecate the name — don't leave `wal`/`snapshots`-style shims implying a capability that's gone.
