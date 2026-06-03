#!/usr/bin/env bash
# Minimal test runner — no bats dependency.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/lib/kiro-gateway.sh"
PASS=0
FAIL=0

expect_output() {
  local name="$1" expected="$2"
  shift 2
  local tmpdir
  tmpdir=$(mktemp -d)
  local actual
  actual=$(KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" bash "$SCRIPT" "$@" 2>&1 || true)
  if echo "$actual" | grep -qF "$expected"; then
    echo "PASS: $name"
    PASS=$((PASS+1))
  else
    echo "FAIL: $name (expected '$expected', got '$actual')"
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

expect_exit() {
  local name="$1" expected_code="$2"
  shift 2
  local tmpdir
  tmpdir=$(mktemp -d)
  local actual_code=0
  KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" bash "$SCRIPT" "$@" >/dev/null 2>&1 || actual_code=$?
  if [[ "$actual_code" == "$expected_code" ]]; then
    echo "PASS: $name"
    PASS=$((PASS+1))
  else
    echo "FAIL: $name (expected exit $expected_code, got $actual_code)"
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

# --- tests ---

expect_output "status no state file shows no state" "no state file" status
expect_output "rollback no previous exits with message" "no previous version" rollback
expect_exit   "rollback no previous exits 1" 1 rollback
expect_exit   "unknown subcommand exits 1" 1 unknown-cmd

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
