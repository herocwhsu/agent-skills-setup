#!/usr/bin/env bash
# Tests for stop-verify.sh (Cross-agent Stop verification wrapper) — no bats.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/stop-verify.sh"
PASS=0
FAIL=0

# Test 1: Clean harness verify allows under Claude/Codex (exit 0)
clean_claude_case() {
  local mock_hooks; mock_hooks=$(mktemp -d)
  printf '#!/bin/sh\nexit 0\n' > "$mock_hooks/registry-guard.sh"
  chmod +x "$mock_hooks/registry-guard.sh"

  local code=0
  printf '{"some":"claude_input"}' | HARNESS_HOOKS_DIR="$mock_hooks" bash "$HOOK" >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 0 ]]; then echo "PASS: clean harness verify allows (exit 0)"; PASS=$((PASS+1))
  else echo "FAIL: clean harness verify allows (expected exit 0, got $code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$mock_hooks"
}
clean_claude_case

# Test 2: Clean harness verify allows under AGY (outputs {} and exit 0)
clean_agy_case() {
  local mock_hooks; mock_hooks=$(mktemp -d)
  printf '#!/bin/sh\nexit 0\n' > "$mock_hooks/registry-guard.sh"
  chmod +x "$mock_hooks/registry-guard.sh"

  local out="" code=0
  out=$(printf '{"executionNum":1,"terminationReason":"model_stop"}' | HARNESS_HOOKS_DIR="$mock_hooks" bash "$HOOK" 2>/dev/null) || code=$?
  if [[ "$code" -eq 0 && "$out" == "{}" ]]; then echo "PASS: AGY clean harness verify outputs {}"; PASS=$((PASS+1))
  else echo "FAIL: AGY clean harness verify outputs {} (code $code, out: $out)"; FAIL=$((FAIL+1)); fi
  rm -rf "$mock_hooks"
}
clean_agy_case

# Test 3: Failing harness verify blocks under Claude/Codex (exit 2, stderr captured)
fail_claude_case() {
  local mock_hooks; mock_hooks=$(mktemp -d)
  printf '#!/bin/sh\necho "mock failure" >&2\nexit 2\n' > "$mock_hooks/registry-guard.sh"
  chmod +x "$mock_hooks/registry-guard.sh"

  local err="" code=0
  err=$(printf '{"some":"claude_input"}' | HARNESS_HOOKS_DIR="$mock_hooks" bash "$HOOK" 2>&1 >/dev/null) || code=$?
  if [[ "$code" -eq 2 && "$err" == *"mock failure"* ]]; then echo "PASS: failing harness verify blocks Claude (exit 2)"; PASS=$((PASS+1))
  else echo "FAIL: failing harness verify blocks Claude (code $code, err: $err)"; FAIL=$((FAIL+1)); fi
  rm -rf "$mock_hooks"
}
fail_claude_case

# Test 4: Failing harness verify instructs AGY to continue (exit 0, JSON decision)
fail_agy_case() {
  local mock_hooks; mock_hooks=$(mktemp -d)
  printf '#!/bin/sh\necho "mock failure" >&2\nexit 2\n' > "$mock_hooks/registry-guard.sh"
  chmod +x "$mock_hooks/registry-guard.sh"

  local out="" code=0
  out=$(printf '{"executionNum":1,"terminationReason":"model_stop"}' | HARNESS_HOOKS_DIR="$mock_hooks" bash "$HOOK" 2>/dev/null) || code=$?
  if [[ "$code" -eq 0 ]] && python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d.get('decision') == 'continue'
assert 'mock failure' in d.get('reason', '')
" "$out" 2>/dev/null; then
    echo "PASS: failing harness verify tells AGY to continue (decision: continue)"; PASS=$((PASS+1))
  else
    echo "FAIL: failing harness verify tells AGY to continue (code $code, out: $out)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$mock_hooks"
}
fail_agy_case

# Test 5: .agents/hooks.json registers Stop hook
agents_case() {
  local hooks_file
  hooks_file="$(cd "$(dirname "$0")/../../.." && pwd)/.agents/hooks.json"
  if [[ -f "$hooks_file" ]] && python3 -c "
import json
d = json.load(open('$hooks_file'))
h = d.get('harness-verify', {}).get('Stop', [])
assert any('stop-verify.sh' in json.dumps(x) for x in h)
" 2>/dev/null; then
    echo "PASS: .agents/hooks.json registers Stop hook"; PASS=$((PASS+1))
  else
    echo "FAIL: .agents/hooks.json registers Stop hook"; FAIL=$((FAIL+1))
  fi
}
agents_case

# Test 6: .codex/hooks.json registers Stop and SubagentStop hooks
codex_case() {
  local hooks_file
  hooks_file="$(cd "$(dirname "$0")/../../.." && pwd)/.codex/hooks.json"
  if [[ -f "$hooks_file" ]] && python3 -c "
import json
d = json.load(open('$hooks_file'))
assert any('stop-verify.sh' in json.dumps(x) for x in d['hooks']['Stop'])
assert any('stop-verify.sh' in json.dumps(x) for x in d['hooks']['SubagentStop'])
" 2>/dev/null; then
    echo "PASS: .codex/hooks.json registers Stop and SubagentStop hooks"; PASS=$((PASS+1))
  else
    echo "FAIL: .codex/hooks.json registers Stop and SubagentStop hooks"; FAIL=$((FAIL+1))
  fi
}
codex_case

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
