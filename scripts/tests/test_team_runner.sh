#!/usr/bin/env bash
# test_team_runner.sh — Unit tests for scripts/team_runner.py and team-runner.sh (feat-062)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0

pass() {
  echo "  PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL  $1"
  FAIL=$((FAIL + 1))
}

# Test 1: team-runner.sh is executable
if [[ -x "$REPO_DIR/scripts/team-runner.sh" ]]; then
  pass "team-runner.sh is executable"
else
  fail "team-runner.sh is not executable"
fi

# Test 2: team-runner.sh --demo passes consensus
output=$(bash "$REPO_DIR/scripts/team-runner.sh" --demo)
if echo "$output" | grep -q "Multi-Agent Team Execution: ACCEPTED" && echo "$output" | grep -q "Consensus Verdict: ACCEPTED"; then
  pass "team-runner.sh --demo completes and reaches consensus"
else
  fail "team-runner.sh --demo failed to reach consensus"
fi

# Test 3: team-runner.sh --demo --simulate-flaw triggers veto
set +e
output_veto=$(bash "$REPO_DIR/scripts/team-runner.sh" --demo --simulate-flaw 2>&1)
exit_code=$?
set -euo pipefail
if [[ $exit_code -eq 1 ]] && echo "$output_veto" | grep -q "VETO TRIGGERED by: sec_auditor"; then
  pass "team-runner.sh --demo --simulate-flaw triggers veto gate"
else
  fail "team-runner.sh --simulate-flaw failed to trigger veto gate"
fi

# Test 4: JSON output flag
json_out=$(bash "$REPO_DIR/scripts/team-runner.sh" --demo --json)
if echo "$json_out" | grep -q '"status": "accepted"' && echo "$json_out" | grep -q '"verdict": "ACCEPTED"'; then
  pass "team-runner.sh --demo --json returns valid structured JSON"
else
  fail "team-runner.sh --demo --json failed to output valid JSON"
fi

# Test 5: Python 3.9 compatibility check
if [[ -x "/usr/bin/python3" ]]; then
  sys_py_out=$(/usr/bin/python3 "$REPO_DIR/scripts/team_runner.py" --demo)
  if echo "$sys_py_out" | grep -q "Multi-Agent Team Execution: ACCEPTED"; then
    pass "scripts/team_runner.py runs cleanly on macOS system python3 (3.9)"
  else
    fail "scripts/team_runner.py failed on macOS system python3"
  fi
else
  pass "macOS system python3 check skipped"
fi

echo ""
echo "test_team_runner.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
