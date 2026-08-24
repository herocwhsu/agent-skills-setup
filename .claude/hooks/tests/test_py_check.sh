#!/usr/bin/env bash
# Tests for py-check.sh (PostToolUse *.py syntax gate) — no bats.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/py-check.sh"
PASS=0
FAIL=0

json_for() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"file_path":sys.stdin.read()}}))'
}

# Args: <name> <expected_exit> <filename> <content>
run_case() {
  local name="$1" expected="$2" fname="$3" content="${4-}"
  local tmp; tmp=$(mktemp -d)
  local code=0
  if [[ -n "$fname" ]]; then
    printf '%s' "$content" > "$tmp/$fname"
    json_for "$tmp/$fname" | bash "$HOOK" >/dev/null 2>&1 || code=$?
  else
    json_for "" | bash "$HOOK" >/dev/null 2>&1 || code=$?
  fi
  if [[ "$code" -eq "$expected" ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected exit $expected, got $code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}

run_case "clean py allows"            0 mod.py $'def f():\n    return 1\n'
run_case "syntax error blocks"        2 mod.py $'def f(:\n    return 1\n'
run_case "bad indent blocks"          2 mod.py $'def f():\nreturn 1\n'
run_case "unterminated string blocks" 2 mod.py $'x = "unclosed\n'
run_case "non-py file ignored"        0 notes.md $'def f(:\n'
run_case "shell file ignored"         0 s.sh     $'if then fi\n'
run_case "empty file_path allows"     0 ""       ''

# Syntax-only by design: a lint-level problem (unused import, no explicit
# subprocess check=) must NOT block, or the hook would gate on the 74
# pre-existing ruff findings this repo carries.
run_case "lint-level issue allows" \
  0 mod.py $'import os\nimport json\n\n\ndef f():\n    return 1\n'

# Missing file must not block (the edit may have been a delete/rename).
missing_case() {
  local tmp; tmp=$(mktemp -d); local code=0
  json_for "$tmp/gone.py" | bash "$HOOK" >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 0 ]]; then echo "PASS: nonexistent file allows"; PASS=$((PASS+1))
  else echo "FAIL: nonexistent file allows (got $code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}
missing_case

# Fail-open posture: unparseable stdin must not block.
fail_open_case() {
  local code=0
  printf 'not json at all' | bash "$HOOK" >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 0 ]]; then echo "PASS: unparseable JSON fails open"; PASS=$((PASS+1))
  else echo "FAIL: unparseable JSON fails open (got $code)"; FAIL=$((FAIL+1)); fi
}
fail_open_case

# The hook accepts `path` as well as `file_path`.
path_key_case() {
  local tmp; tmp=$(mktemp -d); local code=0
  printf 'def f(:\n' > "$tmp/m.py"
  printf '%s' "$tmp/m.py" \
    | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"path":sys.stdin.read()}}))' \
    | bash "$HOOK" >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 2 ]]; then echo "PASS: path key is honored"; PASS=$((PASS+1))
  else echo "FAIL: path key is honored (expected 2, got $code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}
path_key_case

# Regression: the hook must not write __pycache__ beside the checked file.
# This is why it uses ast.parse rather than py_compile — a hook firing on
# every edit must not litter the tree.
no_pycache_case() {
  local tmp; tmp=$(mktemp -d)
  printf 'def f():\n    return 1\n' > "$tmp/mod.py"
  json_for "$tmp/mod.py" | bash "$HOOK" >/dev/null 2>&1 || true
  if [[ -z "$(find "$tmp" -name '__pycache__' -o -name '*.pyc' 2>/dev/null)" ]]; then
    echo "PASS: no __pycache__ or .pyc written"; PASS=$((PASS+1))
  else
    echo "FAIL: no __pycache__ or .pyc written (found artifacts)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmp"
}
no_pycache_case

# The blocking message must name the file and report the line.
message_case() {
  local tmp out; tmp=$(mktemp -d)
  printf 'x = 1\ndef f(:\n' > "$tmp/m.py"
  out=$(json_for "$tmp/m.py" | bash "$HOOK" 2>&1 >/dev/null || true)
  if [[ "$out" == *"m.py"* && "$out" == *"line 2"* ]]; then
    echo "PASS: error message names file and line"; PASS=$((PASS+1))
  else
    echo "FAIL: error message names file and line (got: $out)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmp"
}
message_case

settings_case() {
  local settings
  settings="$(cd "$(dirname "$0")/../.." && pwd)/settings.json"
  if [[ -f "$settings" ]] && python3 -c "
import json
d = json.load(open('$settings'))
h = d['hooks']['PostToolUse']
assert any('py-check.sh' in json.dumps(x) and 'Edit' in x.get('matcher','') for x in h)
" 2>/dev/null; then
    echo "PASS: settings.json registers the PostToolUse py hook"; PASS=$((PASS+1))
  else
    echo "FAIL: settings.json registers the PostToolUse py hook"; FAIL=$((FAIL+1))
  fi
}
settings_case

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
