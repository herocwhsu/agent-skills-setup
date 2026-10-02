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

# The hook accepts AGY `TargetFile` via `toolCall.args`.
agy_target_file_case() {
  local tmp; tmp=$(mktemp -d); local code=0
  printf 'def f(:\n' > "$tmp/m.py"
  printf '%s' "$tmp/m.py" \
    | python3 -c 'import json,sys; print(json.dumps({"toolCall":{"name":"write_to_file","args":{"TargetFile":sys.stdin.read()}}}))' \
    | bash "$HOOK" >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 2 ]]; then echo "PASS: AGY TargetFile key is honored"; PASS=$((PASS+1))
  else echo "FAIL: AGY TargetFile key is honored (expected 2, got $code)"; FAIL=$((FAIL+1)); fi

  # AGY clean file returns exit 0 with {}
  printf 'def f():\n    return 1\n' > "$tmp/clean.py"
  local out
  out=$(printf '%s' "$tmp/clean.py" \
    | python3 -c 'import json,sys; print(json.dumps({"toolCall":{"name":"write_to_file","args":{"TargetFile":sys.stdin.read()}}}))' \
    | bash "$HOOK" 2>/dev/null)
  if [[ "$out" == "{}" ]]; then echo "PASS: AGY clean file outputs {}"; PASS=$((PASS+1))
  else echo "FAIL: AGY clean file outputs {} (got: $out)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}
agy_target_file_case

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

agents_case() {
  local hooks_file
  hooks_file="$(cd "$(dirname "$0")/../../.." && pwd)/.agents/hooks.json"
  if [[ -f "$hooks_file" ]] && python3 -c "
import json
d = json.load(open('$hooks_file'))
h = d.get('syntax-check', {}).get('PostToolUse', [])
assert any('py-check.sh' in json.dumps(x) for x in h)
" 2>/dev/null; then
    echo "PASS: .agents/hooks.json registers the PostToolUse py hook"; PASS=$((PASS+1))
  else
    echo "FAIL: .agents/hooks.json registers the PostToolUse py hook"; FAIL=$((FAIL+1))
  fi
}
agents_case

codex_case() {
  local hooks_file
  hooks_file="$(cd "$(dirname "$0")/../../.." && pwd)/.codex/hooks.json"
  if [[ -f "$hooks_file" ]] && python3 -c "
import json
d = json.load(open('$hooks_file'))
h = d['hooks']['PostToolUse']
assert any('py-check.sh' in json.dumps(x) for x in h)
" 2>/dev/null; then
    echo "PASS: .codex/hooks.json registers the PostToolUse py hook"; PASS=$((PASS+1))
  else
    echo "FAIL: .codex/hooks.json registers the PostToolUse py hook"; FAIL=$((FAIL+1))
  fi
}
codex_case


# Codex edits arrive as tool_name apply_patch; the edited paths exist only in
# the patch text (live capture, 2026-10-02). Paths may be absolute or relative
# to the payload's cwd, and one patch can touch several files.
codex_patch() {  # <cwd> <patch body lines...>
  local cwd="$1"; shift
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"apply_patch","cwd":sys.argv[1],"tool_input":{"command":"*** Begin Patch\n"+"\n".join(sys.argv[2:])+"\n*** End Patch"}}))' "$cwd" "$@"
}
codex_case() {  # <name> <expected_exit> <tmpdir> <patch lines...>
  local name="$1" expected="$2" tmp="$3"; shift 3
  local code=0
  codex_patch "$tmp" "$@" | bash "$HOOK" >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq "$expected" ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected exit $expected, got $code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}

t=$(mktemp -d); printf 'def (:\n' > "$t/a.py"
codex_case "codex apply_patch Add File with python syntax error blocks" 2 "$t" "*** Add File: $t/a.py" "+x"
t=$(mktemp -d); printf 'x = 1\n' > "$t/a.py"
codex_case "codex apply_patch clean python allows" 0 "$t" "*** Update File: $t/a.py" "@@" "+x"
t=$(mktemp -d); printf 'x = 1\n' > "$t/ok.py"; printf 'def (:\n' > "$t/bad.py"
codex_case "codex apply_patch checks every python file in the patch" 2 "$t" "*** Add File: $t/ok.py" "+x" "*** Update File: $t/bad.py" "@@" "+x"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
