#!/usr/bin/env bash
# Tests for scripts/setup-git-hooks.sh
set -euo pipefail

SETUP_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/setup-git-hooks.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# Test 1: Installs pre-commit and pre-push in a real git repo
d="$TMPDIR/repo"
mkdir -p "$d"
( cd "$d" && git init -q )

( cd "$d" && bash "$SETUP_SCRIPT" "$d" >/dev/null 2>&1 )
if [[ -x "$d/.git/hooks/pre-commit" && -x "$d/.git/hooks/pre-push" ]]; then
  ok "installs executable pre-commit and pre-push hooks"
else
  bad "installs executable pre-commit and pre-push hooks" "hooks missing or not executable"
fi

# Test 2: Hooks contain correct execution targets
if grep -q "bash-compat-guard.sh" "$d/.git/hooks/pre-commit" && grep -q "harness-verify.sh" "$d/.git/hooks/pre-push"; then
  ok "hooks invoke bash-compat-guard and harness-verify"
else
  bad "hooks invoke bash-compat-guard and harness-verify" "hook content unexpected"
fi

echo ""
echo "test_setup_git_hooks: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
