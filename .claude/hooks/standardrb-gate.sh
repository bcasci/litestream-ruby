#!/usr/bin/env bash
# PostToolUse gate: block on standardrb violations or a missing
# frozen_string_literal comment in an edited Ruby file. Reads the Claude Code
# hook payload from stdin; exits 2 (guidance on stderr) so the change is fixed
# before it's considered done. Non-Ruby edits pass through untouched.

payload=$(cat)
file=$(printf '%s' "$payload" | ASDF_RUBY_VERSION=3.3.8 ruby -rjson -e \
  'print(JSON.parse($stdin.read).dig("tool_input", "file_path").to_s) rescue print("")' 2>/dev/null)

case "$file" in
  *.rb) ;;
  *) exit 0 ;;
esac

[ -f "$file" ] || exit 0

problems=""

if ! lint=$(ASDF_RUBY_VERSION=3.3.8 bundle exec standardrb "$file" 2>&1); then
  problems+="$lint"$'\n'
fi

if ! head -2 "$file" | grep -q 'frozen_string_literal: true'; then
  problems+="Missing '# frozen_string_literal: true' at the top of the file (standards/ruby-idioms rule 1)."$'\n'
fi

[ -z "$problems" ] && exit 0

{
  echo "Standards gate failed for $file:"
  printf '%s' "$problems"
  echo "Fix before finishing (autofix lint: ASDF_RUBY_VERSION=3.3.8 bundle exec standardrb --fix \"$file\")."
} >&2
exit 2
