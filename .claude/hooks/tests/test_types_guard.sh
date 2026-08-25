#!/usr/bin/env bash
# Tests for types-guard.sh (Stop/SubagentStop mypy gate) — no bats.
#
# Points the hook at throwaway git repos via TYPES_GUARD_REPO_DIR. Asserting
# only against the real tree would prove nothing once the tree is clean, and a
# gate that cannot be shown to fail is the no-op that hooks/common/sh-check.sh
# used to be.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/types-guard.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# make_repo <name> <file-content> -> path to a git repo with mod.py tracked
make_repo() {
  local d="$TMPDIR/$1"
  mkdir -p "$d"
  ( cd "$d"
    git init -q
    git config user.email t@t; git config user.name t
    printf '%s' "$2" > mod.py
    git add mod.py ) >/dev/null 2>&1
  echo "$d"
}

run_hook() { TYPES_GUARD_REPO_DIR="$1" bash "$HOOK" 2>&1; }

if ! command -v mypy >/dev/null 2>&1 || ! mypy --version >/dev/null 2>&1; then
  echo "  SKIP  mypy unavailable — gate behaviour cannot be asserted"
  echo ""
  echo "test_types_guard: 0 passed, 0 failed (skipped)"
  exit 0
fi

# --- a clean repo is allowed ---
d=$(make_repo clean 'def f(x: int) -> int:
    return x + 1
')
code=0; out=$(run_hook "$d") || code=$?
[[ $code -eq 0 ]] && ok "clean tree exits 0" || bad "clean tree exits 0" "exit $code: $out"

# --- a type error blocks with exit 2, not 1 ---
d=$(make_repo bad 'def f(x: int) -> int:
    return x + 1


bad: int = "not an int"
')
code=0; out=$(run_hook "$d") || code=$?
if [[ $code -eq 2 ]]; then
  ok "type error blocks with exit 2"
else
  bad "type error blocks with exit 2" "got exit $code (1 would not block)"
fi
grep -q 'Blocked' <<<"$out" \
  && ok "block message is emitted" \
  || bad "block message is emitted" "out: $out"
grep -qE 'assignment|Incompatible' <<<"$out" \
  && ok "mypy output is surfaced, not swallowed" \
  || bad "mypy output is surfaced" "out: $out"

# --- a syntax error also blocks (mypy parses before it types) ---
d=$(make_repo syntax 'def broken(:
')
code=0; run_hook "$d" >/dev/null 2>&1 || code=$?
[[ $code -eq 2 ]] && ok "syntax error blocks" || bad "syntax error blocks" "got exit $code"

# --- a repo with no python is allowed, not an error ---
d="$TMPDIR/nopy"; mkdir -p "$d"
( cd "$d"; git init -q; git config user.email t@t; git config user.name t
  echo hi > README.md; git add README.md ) >/dev/null 2>&1
code=0; run_hook "$d" >/dev/null 2>&1 || code=$?
[[ $code -eq 0 ]] && ok "repo with no python exits 0" || bad "repo with no python exits 0" "exit $code"

# --- untracked files are ignored (the gate reads git ls-files) ---
d=$(make_repo untracked 'def f(x: int) -> int:
    return x + 1
')
printf 'nope: int = "bad"\n' > "$d/scratch.py"   # deliberately not git-added
code=0; run_hook "$d" >/dev/null 2>&1 || code=$?
if [[ $code -eq 0 ]]; then
  ok "untracked python is not gated"
else
  bad "untracked python is not gated" "exit $code — scratch files would block work"
fi

# --- whole-tree, not per-file ---
# Invoking mypy per file re-reports errors that live in imported modules, so
# `mypy a.py` shows b.py's errors too and counts them once per importer.
grep -q 'xargs -0 mypy' "$HOOK" \
  && ok "invokes mypy once over all files" \
  || bad "invokes mypy once over all files" "per-file invocation triple-counts"

# --- registered in settings.json for both stop events ---
SETTINGS="$(cd "$(dirname "$0")/../.." && pwd)/settings.json"
if python3 -c "
import json, sys
d = json.load(open('$SETTINGS'))
for ev in ('Stop', 'SubagentStop'):
    hooks = [h for e in d['hooks'][ev] for h in e['hooks']]
    assert any('types-guard.sh' in h['command'] for h in hooks), ev
" 2>/dev/null; then
  ok "registered in Stop and SubagentStop"
else
  bad "registered in Stop and SubagentStop" "missing from settings.json"
fi

echo ""
echo "test_types_guard: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
