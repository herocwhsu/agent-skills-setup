#!/usr/bin/env bash
# Tests for .claude/hooks/bash-compat-guard.sh.
#
# Uses BASH_COMPAT_GUARD_REPO_DIR to point at throwaway trees; the real tree is
# clean, so asserting only against it would stop being a test immediately.
#
# Fixtures are written with printf on one line so this file never contains a
# Bash 4 construct in command position itself -- the guard scans this file too.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_DIR/.claude/hooks/bash-compat-guard.sh"
[[ -f "$HOOK" ]] || { echo "FAIL: hook not found at $HOOK"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# tree <name> <relpath> <printf-format> -> echoes a dir containing one file
tree() {
  local d="$TMP/$1"
  mkdir -p "$d/$(dirname "$2")"
  # shellcheck disable=SC2059
  printf "$3" > "$d/$2"
  echo "$d"
}

run_hook() { BASH_COMPAT_GUARD_REPO_DIR="$1" bash "$HOOK" 2>&1; }

expect_block() {
  local label="$1" d="$2" out code
  out=$(run_hook "$d") && code=0 || code=$?
  if [[ $code -eq 2 ]]; then ok "$label"
  else bad "$label" "exit $code, out: $out"; fi
}

expect_pass() {
  local label="$1" d="$2" out code
  out=$(run_hook "$d") && code=0 || code=$?
  if [[ $code -eq 0 ]]; then ok "$label"
  else bad "$label" "exit $code, out: $out"; fi
}

# --- constructs that abort under macOS /bin/bash 3.2 -----------------------
expect_block "mapfile blocks"          "$(tree mapfile   s/a.sh 'set -e\nmapfile -t lines < f\n')"
expect_block "indented readarray blocks" "$(tree readarr s/a.sh 'if true; then\n  readarray -t x < f\nfi\n')"
expect_block "mapfile after ; blocks"  "$(tree mapsemi   s/a.sh 'cd /\073 mapfile -t x < f\n')"
expect_block "declare -A blocks"       "$(tree declA     s/a.sh 'declare -A seen\n')"
expect_block "local -A blocks"         "$(tree localA    s/a.sh 'f() {\n  local -A m\n}\n')"
expect_block "declare -gA blocks"      "$(tree declgA    s/a.sh 'declare -gA m\n')"
# The init-repo.sh incident: ;& shipped for months while CI (bash 5) stayed green.
expect_block ";& fallthrough blocks"   "$(tree fall      s/a.sh 'case $1 in\n  a) echo a ;&\n  b) echo b ;;\nesac\n')"
expect_block ";;& fallthrough blocks"  "$(tree fall2     s/a.sh 'case $1 in\n  a) echo a ;;&\n  *) echo b ;;\nesac\n')"

out=$(run_hook "$(tree msg hooks/x.sh 'echo hi\nmapfile -t x < f\n')") || true
grep -q 'hooks/x.sh:2' <<<"$out" \
  && ok "message names file and line" \
  || bad "message names file and line" "out: $out"

# --- things that merely mention the constructs must not block --------------
expect_pass "comments are ignored"     "$(tree comment   s/a.sh '# no mapfile here (bash 3.2)\necho ok # avoid declare -A\n')"
d=$(tree quoted s/a.sh 'echo "found declare -A"\n')
printf '%s\n' "grep -nwE 'mapfile|readarray' \"\$f\"" >> "$d/s/a.sh"
expect_pass "quoted strings are ignored" "$d"
expect_pass "bash 3.2-safe script passes" "$(tree safe   s/a.sh 'declare -a arr\nlocal x=1 2>&1 >&2\ncase $1 in a) x ;; esac\n')"
expect_pass "non-.sh files are not scanned" "$(tree md   docs/a.md 'mapfile -t x < f\n')"

d=$(tree venv s/ok.sh 'echo ok\n')
mkdir -p "$d/.venv/bin" "$d/.git"
printf 'mapfile -t x < f\n' > "$d/.venv/bin/activate.sh"
printf 'declare -A m\n' > "$d/.git/hook.sh"
expect_pass ".venv and .git are skipped" "$d"

# --- the real tree passes --------------------------------------------------
out=$(bash "$HOOK" 2>&1) && code=0 || code=$?
[[ $code -eq 0 ]] \
  && ok "the repo's own shell scripts are clean" \
  || bad "the repo's own shell scripts are clean" "exit $code, out: $out"

echo ""
echo "test_bash_compat_guard: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
