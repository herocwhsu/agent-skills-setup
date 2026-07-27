#!/usr/bin/env bash
# Tests for precommit-sh-check.sh — no bats.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/precommit-sh-check.sh"
PASS=0
FAIL=0

# Run the hook with a synthetic command in a throwaway git repo.
# Args: <name> <expected_exit> <commit_command> <staged_file_content>
run_case() {
  local name="$1" expected="$2" cmd="$3" content="${4-}"
  local tmp; tmp=$(mktemp -d)
  local code=0
  ( cd "$tmp"
    git init -q
    git config user.email t@t; git config user.name t
    if [[ -n "$content" ]]; then
      printf '%s' "$content" > script.sh
      git add script.sh
    fi
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
      | bash "$HOOK" >/dev/null 2>&1
  ) || code=$?
  if [[ "$code" -eq "$expected" ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected exit $expected, got $code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}

run_case "clean staged sh allows"        0 'git commit -m x' $'#!/usr/bin/env bash\necho ok\n'
run_case "syntax error blocks"           2 'git commit -m x' $'#!/usr/bin/env bash\nif then fi\n'
run_case "non-commit bash allows"        0 'git status'      $'#!/usr/bin/env bash\nif then fi\n'
run_case "dry-run allows"                0 'git commit --dry-run' $'#!/usr/bin/env bash\nif then fi\n'
run_case "no staged sh allows"           0 'git commit -m x' ''

if command -v shellcheck >/dev/null 2>&1; then
  # SC2086-class issues are warnings; use an error-level construct.
  run_case "shellcheck error blocks" 2 'git commit -m x' $'#!/usr/bin/env bash\necho "$(\n'
fi

settings_valid_test() {
  local name="$1"
  local settings
  settings="$(cd "$(dirname "$0")/../.." && pwd)/settings.json"
  if [[ -f "$settings" ]] \
     && python3 -c "import json,sys; d=json.load(open('$settings')); h=d['hooks']['PreToolUse']; assert any('precommit-sh-check.sh' in json.dumps(x) for x in h)" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (settings missing or hook not registered)"; FAIL=$((FAIL+1))
  fi
}
settings_valid_test "settings.json registers the PreToolUse hook"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
