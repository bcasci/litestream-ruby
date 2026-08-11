# Error Handling & Messages

1. Give each distinct failure mode its own typed exception (never a bare `RuntimeError`), defined as `Name = Class.new(StandardError)` with a `# raised when …` comment.
2. Guard required arguments at method entry and raise with a copy-pasteable example invocation (e.g. `litestream:restore -- --database=path/to/db.sqlite`).
3. Write remediation messages as `<<~` heredocs with the exact shell commands and a doc URL. Tell the user how to recover, not just what broke.
4. Apply that richness consistently — no bare one-line raise where a remediation heredoc belongs.
5. Detect command failure from parsed output and re-raise as `CommandFailedException` embedding the command and the underlying reason. Don't swallow the real error with a bare `rescue`.
6. Put all resource cleanup in an `ensure` block, and nil-guard it so cleanup never masks the original error.
7. Don't let a domain exception escape as an unhandled 500 — rescue in controllers and surface a remediation message, matching the CLI paths.

(Removed/renamed upstream commands raise `CommandNotSupportedException` — see [extensibility](extensibility.md).)
