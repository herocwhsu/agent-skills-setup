#!/usr/bin/env bash
# test_ratchet_loop.sh — Unit tests for scripts/ratchet_loop.py and ratchet-loop.sh (feat-058)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

# Test 1: ratchet-loop.sh is executable
if [[ -x "$REPO_DIR/scripts/ratchet-loop.sh" ]]; then
  pass "ratchet-loop.sh is executable"
else
  fail "ratchet-loop.sh is not executable"
fi

# Test 2: ratchet-loop.sh --demo executes synthetic ratchet loop successfully
output=$(bash "$REPO_DIR/scripts/ratchet-loop.sh" --demo)
if echo "$output" | grep -q "Autonomous Ratchet Loop Demo" && echo "$output" | grep -q "Loop State: Demo Optimization Loop"; then
  pass "ratchet-loop.sh --demo runs synthetic loop to completion"
else
  fail "ratchet-loop.sh --demo output missing expected summary"
fi

# Test 3: ratchet-loop.sh --goal-file parses docs/goals/TEMPLATE.md
output=$(bash "$REPO_DIR/scripts/ratchet-loop.sh" --goal-file "$REPO_DIR/docs/goals/TEMPLATE.md")
if echo "$output" | grep -q "Loaded Goal Specification" && echo "$output" | grep -q "Acceptance Criteria"; then
  pass "ratchet-loop.sh --goal-file parses goal specification"
else
  fail "ratchet-loop.sh --goal-file failed to parse template"
fi

# Test 4: ratchet-loop.sh --active-feature reads active feature with test isolation
cat << 'EOF' > "$TMP_DIR/feature_list.json"
{
  "features": [
    {
      "id": "feat-999",
      "name": "Mock Active Feature",
      "description": "Mock description",
      "status": "in_progress",
      "acceptance_criteria": ["Mock criteria"],
      "verification": "true"
    }
  ]
}
EOF

output=$(bash "$REPO_DIR/scripts/ratchet-loop.sh" --repo-dir "$TMP_DIR" --active-feature)
if echo "$output" | grep -q "Loaded Active Feature Goal" && echo "$output" | grep -q "feat-999"; then
  pass "ratchet-loop.sh --active-feature loads active feature from feature_list.json"
else
  fail "ratchet-loop.sh --active-feature failed to load active feature"
fi

# Test 5: ratchet-loop.sh error handling on non-existent goal file
set +e
err_out=$(bash "$REPO_DIR/scripts/ratchet-loop.sh" --goal-file "$REPO_DIR/docs/goals/non-existent.md" 2>&1)
rc=$?
set -euo pipefail
if [[ $rc -ne 0 ]] && echo "$err_out" | grep -q "Goal file not found"; then
  pass "ratchet-loop.sh handles non-existent goal file cleanly"
else
  fail "ratchet-loop.sh failed to handle non-existent goal file"
fi

# Test 6: Python 3.9 compatibility for scripts/ratchet_loop.py
if [[ -x "/usr/bin/python3" ]]; then
  sys_py_out=$(/usr/bin/python3 "$REPO_DIR/scripts/ratchet_loop.py" --demo)
  if echo "$sys_py_out" | grep -q "COMPLETED"; then
    pass "scripts/ratchet_loop.py runs cleanly on macOS system python3 (3.9)"
  else
    fail "scripts/ratchet_loop.py failed on macOS system python3"
  fi
else
  pass "macOS system python3 check skipped (not available)"
fi

echo ""
echo "test_ratchet_loop.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
