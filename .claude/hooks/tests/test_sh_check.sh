#!/usr/bin/env bash
# Tests for sh-check.sh (PostToolUse *.sh syntax + shellcheck gate) — no bats.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/sh-check.sh"
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

run_case "clean sh allows"              0 script.sh $'#!/usr/bin/env bash\necho ok\n'
run_case "syntax error blocks"          2 script.sh $'#!/usr/bin/env bash\nif then fi\n'
run_case "unterminated quote blocks"    2 script.sh $'#!/usr/bin/env bash\necho "unclosed\n'
run_case "non-sh file ignored"          0 notes.md  $'if then fi\n'
run_case "python file ignored"          0 thing.py  $'def (:\n'
run_case "empty file_path allows"       0 ""        ''

# Missing file must not block (the edit may have been a delete/rename).
missing_case() {
  local tmp; tmp=$(mktemp -d); local code=0
  json_for "$tmp/gone.sh" | bash "$HOOK" >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 0 ]]; then echo "PASS: nonexistent file allows"; PASS=$((PASS+1))
  else echo "FAIL: nonexistent file allows (got $code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}
missing_case

# Fail-open posture: unparseable stdin must not block, matching
# precommit-sh-check.sh.
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
  printf '%s' "$tmp/s.sh" > /dev/null
  printf '#!/usr/bin/env bash\nif then fi\n' > "$tmp/s.sh"
  printf '%s' "$tmp/s.sh" \
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
  printf '#!/usr/bin/env bash\nif then fi\n' > "$tmp/s.sh"
  printf '%s' "$tmp/s.sh" \
    | python3 -c 'import json,sys; print(json.dumps({"toolCall":{"name":"write_to_file","args":{"TargetFile":sys.stdin.read()}}}))' \
    | bash "$HOOK" >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 2 ]]; then echo "PASS: AGY TargetFile key is honored"; PASS=$((PASS+1))
  else echo "FAIL: AGY TargetFile key is honored (expected 2, got $code)"; FAIL=$((FAIL+1)); fi

  # AGY clean file returns exit 0 with {}
  printf '#!/usr/bin/env bash\necho ok\n' > "$tmp/clean.sh"
  local out
  out=$(printf '%s' "$tmp/clean.sh" \
    | python3 -c 'import json,sys; print(json.dumps({"toolCall":{"name":"write_to_file","args":{"TargetFile":sys.stdin.read()}}}))' \
    | bash "$HOOK" 2>/dev/null)
  if [[ "$out" == "{}" ]]; then echo "PASS: AGY clean file outputs {}"; PASS=$((PASS+1))
  else echo "FAIL: AGY clean file outputs {} (got: $out)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}
agy_target_file_case

if command -v shellcheck >/dev/null 2>&1; then
  run_case "shellcheck error blocks" 2 script.sh $'#!/usr/bin/env bash\necho "$(\n'
  # Severity boundary: the repo carries warning/info-level diagnostics, so a
  # sub-error finding (here SC2086, unquoted expansion) must NOT block.
  run_case "sub-error shellcheck finding allows" \
    0 script.sh $'#!/usr/bin/env bash\nv=1\necho $v\n'
fi

settings_case() {
  local settings
  settings="$(cd "$(dirname "$0")/../.." && pwd)/settings.json"
  if [[ -f "$settings" ]] && python3 -c "
import json
d = json.load(open('$settings'))
h = d['hooks']['PostToolUse']
assert any('sh-check.sh' in json.dumps(x) and 'Edit' in x.get('matcher','') for x in h)
" 2>/dev/null; then
    echo "PASS: settings.json registers the PostToolUse sh hook"; PASS=$((PASS+1))
  else
    echo "FAIL: settings.json registers the PostToolUse sh hook"; FAIL=$((FAIL+1))
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
assert any('sh-check.sh' in json.dumps(x) for x in h)
" 2>/dev/null; then
    echo "PASS: .agents/hooks.json registers the PostToolUse sh hook"; PASS=$((PASS+1))
  else
    echo "FAIL: .agents/hooks.json registers the PostToolUse sh hook"; FAIL=$((FAIL+1))
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
assert any('sh-check.sh' in json.dumps(x) for x in h)
" 2>/dev/null; then
    echo "PASS: .codex/hooks.json registers the PostToolUse sh hook"; PASS=$((PASS+1))
  else
    echo "FAIL: .codex/hooks.json registers the PostToolUse sh hook"; FAIL=$((FAIL+1))
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

t=$(mktemp -d); printf '#!/usr/bin/env bash\nif then fi\n' > "$t/a.sh"
codex_case "codex apply_patch Add File with syntax error blocks" 2 "$t" "*** Add File: $t/a.sh" "+x"
t=$(mktemp -d); printf '#!/usr/bin/env bash\necho ok\n' > "$t/a.sh"
codex_case "codex apply_patch Update File clean allows" 0 "$t" "*** Update File: $t/a.sh" "@@" "+x"
t=$(mktemp -d); printf '#!/usr/bin/env bash\nif then fi\n' > "$t/rel.sh"
codex_case "codex apply_patch relative path resolves against cwd" 2 "$t" "*** Add File: rel.sh" "+x"
t=$(mktemp -d); printf '#!/usr/bin/env bash\necho ok\n' > "$t/ok.sh"; printf '#!/usr/bin/env bash\nif then fi\n' > "$t/bad.sh"
codex_case "codex apply_patch checks every file in the patch" 2 "$t" "*** Add File: $t/ok.sh" "+x" "*** Update File: $t/bad.sh" "@@" "+x"
t=$(mktemp -d); printf '#!/usr/bin/env bash\nif then fi\n' > "$t/new.sh"
codex_case "codex apply_patch Move to checks the new path" 2 "$t" "*** Update File: $t/old.sh" "*** Move to: $t/new.sh" "@@" "+x"
t=$(mktemp -d)
codex_case "codex apply_patch Delete File allows" 0 "$t" "*** Delete File: $t/gone.sh"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
