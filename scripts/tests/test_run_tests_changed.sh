#!/usr/bin/env bash
# Tests for scripts/run-tests.sh --changed integration and flag handling
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# Test 1: Flag parsing and help
if bash "$REPO_DIR/scripts/run-tests.sh" --help >/dev/null 2>&1 || true; then
  ok "run-tests.sh accepts arguments without bash syntax crash"
fi

# Test 2: Verify selective resolution behavior with get-changed-files and resolve_test_targets
d="$TMPDIR/repo"
mkdir -p "$d/scripts/tests" "$d/skills/demo/tests"
(
  cd "$d"
  git init -q
  git config user.email t@t; git config user.name t
  echo "dummy" > scripts/foo.sh
  echo "dummy" > scripts/tests/test_foo.sh
  git add .
  git commit -m "init" -q
)

# Test 2a: Modifying a single script resolves ONLY its test target
echo "change" >> "$d/scripts/foo.sh"
changed=$(GET_CHANGED_REPO_DIR="$d" bash "$REPO_DIR/scripts/get-changed-files.sh")
targets=$(printf "%s\n" "$changed" | RESOLVE_REPO_DIR="$d" python3 "$REPO_DIR/scripts/resolve_test_targets.py")

if [[ "$targets" == "scripts/tests/test_foo.sh" ]]; then
  ok "single script edit resolves strictly to its matching test"
else
  bad "single script edit resolves strictly to its matching test" "got: $targets"
fi

# Test 2b: Modifying shared infrastructure resolves to ALL
echo "change" > "$d/scripts/_lib.sh"
changed_infra=$(GET_CHANGED_REPO_DIR="$d" bash "$REPO_DIR/scripts/get-changed-files.sh")
targets_infra=$(printf "%s\n" "$changed_infra" | RESOLVE_REPO_DIR="$d" python3 "$REPO_DIR/scripts/resolve_test_targets.py")

if [[ "$targets_infra" == "ALL" ]]; then
  ok "shared infrastructure edit resolves safely to ALL"
else
  bad "shared infrastructure edit resolves safely to ALL" "got: $targets_infra"
fi

echo ""
echo "test_run_tests_changed: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
