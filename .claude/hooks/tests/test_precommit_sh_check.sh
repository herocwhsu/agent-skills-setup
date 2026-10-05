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

# Regression: flag-like/subcommand-like text inside the -m message must NOT be
# mistaken for a real flag or subcommand (token-level classification).
run_case "dry-run text in message still blocks" 2 'git commit -m "fix --dry-run handling"' $'#!/usr/bin/env bash\nif then fi\n'
run_case "help text in message still blocks"    2 'git commit -m "document --help output"' $'#!/usr/bin/env bash\nif then fi\n'
run_case "commit word in echo does not block"   0 'echo "please git commit later"' $'#!/usr/bin/env bash\nif then fi\n'

# Regression: a commit chained after another git command must still be gated.
# The classifier used to stop at the first `git` token, so `git add x && git
# commit` was never checked (found live under AGY, 2026-10-02).
run_case "chained add && commit blocks"         2 'git add script.sh && git commit -m x' $'#!/usr/bin/env bash\nif then fi\n'
run_case "unspaced ; chained commit blocks"     2 'git status;git commit -m x' $'#!/usr/bin/env bash\nif then fi\n'
run_case "--help in a later command still blocks" 2 'git commit -m x && git log --help' $'#!/usr/bin/env bash\nif then fi\n'
run_case "chained non-commit git allows"        0 'git add script.sh && git status' $'#!/usr/bin/env bash\nif then fi\n'

if command -v shellcheck >/dev/null 2>&1; then
  # SC2086-class issues are warnings; use an error-level construct.
  run_case "shellcheck error blocks" 2 'git commit -m x' $'#!/usr/bin/env bash\necho "$(\n'
fi

# AGY PreToolUse: returns exit 0 with JSON decision on stdout
run_agy_case() {
  local name="$1" expected_decision="$2" cmd="$3" content="${4-}"
  local tmp; tmp=$(mktemp -d)
  local out=""
  ( cd "$tmp"
    git init -q
    git config user.email t@t; git config user.name t
    if [[ -n "$content" ]]; then
      printf '%s' "$content" > script.sh
      git add script.sh
    fi
    printf '{"toolCall":{"name":"run_command","args":{"CommandLine":%s}}}' \
      "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
      | bash "$HOOK" 2>/dev/null
  ) > "$tmp/out" || true
  out=$(cat "$tmp/out")
  if python3 -c "
import json, sys
d = json.loads(sys.argv[1]) if sys.argv[1].strip() else {}
exp = sys.argv[2]
if exp == 'deny':
    assert d.get('decision') == 'deny', f'expected deny, got {d}'
elif exp == 'allow':
    assert d.get('decision') in ('allow', None), f'expected allow, got {d}'
" "$out" "$expected_decision" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (unexpected AGY output: $out)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmp"
}

run_agy_case "AGY syntax error denies" "deny" 'git commit -m x' $'#!/usr/bin/env bash\nif then fi\n'
run_agy_case "AGY clean staged allows" "allow" 'git commit -m x' $'#!/usr/bin/env bash\necho ok\n'
run_agy_case "AGY chained add && commit denies" "deny" 'git add script.sh && git commit -m "test: broken"' $'#!/usr/bin/env bash\nif then fi\n'

settings_valid_test() {
  local name="$1"
  local settings
  settings="$(cd "$(dirname "$0")/../.." && pwd)/settings.json"
  if [[ -f "$settings" ]] \
     && python3 -c "import json,sys; d=json.load(open('$settings')); h=d['hooks']['PreToolUse']; assert any(x.get('matcher')=='Bash' and 'precommit-sh-check.sh' in json.dumps(x) for x in h)" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (settings missing or hook not registered)"; FAIL=$((FAIL+1))
  fi
}
settings_valid_test "settings.json registers the PreToolUse hook"

agents_valid_test() {
  local name="$1"
  local hooks_file
  hooks_file="$(cd "$(dirname "$0")/../../.." && pwd)/.agents/hooks.json"
  if [[ -f "$hooks_file" ]] \
     && python3 -c "import json,sys; d=json.load(open('$hooks_file')); assert 'precommit-sh-check' in d" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (.agents/hooks.json missing or precommit-sh-check not registered)"; FAIL=$((FAIL+1))
  fi
}
agents_valid_test ".agents/hooks.json registers the PreToolUse hook"

# AGY kills a hook at 30s by default. Under load (two agents plus harness-verify)
# this gate was killed mid-run on 2026-10-05 while it takes ~3s, which blocks
# commits with an empty "signal: killed" instead of a real verdict.
agents_timeout_test() {
  local hooks_file
  hooks_file="$(cd "$(dirname "$0")/../../.." && pwd)/.agents/hooks.json"
  if python3 -c "
import json
d = json.load(open('$hooks_file'))
h = [x for g in d['precommit-sh-check']['PreToolUse'] for x in g['hooks'] if 'precommit-sh-check.sh' in x['command']]
assert h and all(int(x.get('timeout', 0)) >= 120 for x in h)
" 2>/dev/null; then
    echo "PASS: .agents/hooks.json pre-commit hook sets timeout >= 120s"; PASS=$((PASS+1))
  else
    echo "FAIL: .agents/hooks.json pre-commit hook sets timeout >= 120s"; FAIL=$((FAIL+1))
  fi
}
agents_timeout_test

codex_valid_test() {
  local name="$1"
  local hooks_file
  hooks_file="$(cd "$(dirname "$0")/../../.." && pwd)/.codex/hooks.json"
  if [[ -f "$hooks_file" ]] \
     && python3 -c "import json,sys; d=json.load(open('$hooks_file')); h=d['hooks']['PreToolUse']; assert any('precommit-sh-check.sh' in json.dumps(x) for x in h)" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (.codex/hooks.json missing or precommit-sh-check not registered)"; FAIL=$((FAIL+1))
  fi
}
codex_valid_test ".codex/hooks.json registers the PreToolUse hook"


# Real agent shape: the file is NOT staged when the hook runs, because the
# hook fires before the command, and the command itself stages it (live
# capture under AGY and Codex, 2026-10-02). Earlier cases staged in advance.
run_unstaged_case() {  # <name> <expected_exit> <command> <untracked|modified>
  local name="$1" expected="$2" cmd="$3" mode="$4"
  local tmp; tmp=$(mktemp -d); local code=0
  ( cd "$tmp"
    git init -q; git config user.email t@t; git config user.name t
    if [[ "$mode" == modified ]]; then
      printf '#!/usr/bin/env bash\necho ok\n' > script.sh
      git add script.sh; git commit -q -m init
    fi
    printf '#!/usr/bin/env bash\nif then fi\n' > script.sh
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
      | bash "$HOOK" >/dev/null 2>&1
  ) || code=$?
  if [[ "$code" -eq "$expected" ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected exit $expected, got $code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}
run_unstaged_case "add file && commit checks the file being added" 2 'git add script.sh && git commit -m x' untracked
run_unstaged_case "add . && commit checks untracked scripts"       2 'git add . && git commit -m x' untracked
run_unstaged_case "add -A && commit checks untracked scripts"      2 'git add -A && git commit -m x' untracked
run_unstaged_case "commit -am checks modified tracked scripts"     2 'git commit -am x' modified
run_unstaged_case "commit -a -m checks modified tracked scripts"   2 'git commit -a -m x' modified
run_unstaged_case "adding an unrelated file does not gate others"  0 'git add notes.txt && git commit -m x' untracked
run_unstaged_case "plain commit ignores unstaged changes"          0 'git commit -m x' modified

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
