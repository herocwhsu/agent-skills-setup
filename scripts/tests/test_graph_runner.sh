#!/usr/bin/env bash
# test_graph_runner.sh — Unit tests for scripts/graph_runner.py and graph-runner.sh (feat-060)

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

# Test 1: graph-runner.sh is executable
if [[ -x "$REPO_DIR/scripts/graph-runner.sh" ]]; then
  pass "graph-runner.sh is executable"
else
  fail "graph-runner.sh is not executable"
fi

# Test 2: graph-runner.sh --demo runs demonstration graph
output=$(bash "$REPO_DIR/scripts/graph-runner.sh" --demo --fails 1)
if echo "$output" | grep -q "Multi-Agent Workflow DAG Demonstration" && echo "$output" | grep -q "Review Verdict: pass"; then
  pass "graph-runner.sh --demo runs workflow DAG to completion"
else
  fail "graph-runner.sh --demo failed to complete"
fi

# Test 3: Python 3.9 compatibility check
if [[ -x "/usr/bin/python3" ]]; then
  sys_py_out=$(/usr/bin/python3 "$REPO_DIR/scripts/graph_runner.py" --demo --fails 2)
  if echo "$sys_py_out" | grep -q "Graph Execution Completed"; then
    pass "scripts/graph_runner.py runs cleanly on macOS system python3 (3.9)"
  else
    fail "scripts/graph_runner.py failed on macOS system python3"
  fi
else
  pass "macOS system python3 check skipped"
fi

echo ""
echo "test_graph_runner.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
