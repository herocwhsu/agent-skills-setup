#!/usr/bin/env bash
# test_init_repo.sh — tests for scripts/init-repo.sh
#
# Motivated by a real bug: init-repo.sh shipped three bash 4.0+ `;&` case
# terminators, so it aborted with a parse error on the bash 3.2 that macOS
# ships as /bin/bash, after copying only 5 of 16 hooks. Nothing caught it —
# CI runs ubuntu-latest (bash 5, which accepts `;&`) and no test exercised
# the script at all.
#
# That is why the portability check below greps for bash-4-only constructs
# explicitly instead of relying on `bash -n`: on a bash 5 runner `bash -n`
# parses `;&` happily, so a syntax check alone would not have caught it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/init-repo.sh"
HOOKS_SRC="$(cd "$SCRIPT_DIR/../hooks" && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# Every target is a throwaway dir. Never point init-repo.sh at this repo —
# it would overwrite the repo's own .claude/hooks/.
target() { local d="$TMPDIR/$1"; mkdir -p "$d"; echo "$d"; }

# --- parses under the running shell ------------------------------------------
if bash -n "$SCRIPT" 2>/dev/null; then
  ok "parses under bash $(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
else
  bad "parses under the running bash" "bash -n failed"
fi

# --- portability: no bash 4+ only constructs ---------------------------------
# Anchored to the case-terminator form so a `;&` inside a string or regex does
# not produce a false positive.
if grep -nE '^[[:space:]]*;;?&[[:space:]]*$' "$SCRIPT" >/dev/null 2>&1; then
  bad "no bash 4 case fallthrough terminators" \
      "found $(grep -cE '^[[:space:]]*;;?&[[:space:]]*$' "$SCRIPT") (';&' / ';;&' need bash 4)"
else
  ok "no bash 4 case fallthrough terminators"
fi

if grep -nwE 'mapfile|readarray' "$SCRIPT" >/dev/null 2>&1; then
  bad "no bash 4 mapfile/readarray" "found $(grep -cwE 'mapfile|readarray' "$SCRIPT")"
else
  ok "no bash 4 mapfile/readarray"
fi

if grep -nE 'declare[[:space:]]+-[A-Za-z]*A' "$SCRIPT" >/dev/null 2>&1; then
  bad "no bash 4 associative arrays" "found declare -A"
else
  ok "no bash 4 associative arrays"
fi

# --- profile: full copies EVERY template ------------------------------------
# "full — everything" is the documented contract. Deriving the expectation from
# the template tree rather than a hardcoded count means adding a template
# without wiring it into the full profile fails here — the exact mistake that
# left py-check.sh uncopied when it was first written.
t=$(target full)
if out=$(bash "$SCRIPT" full "$t" 2>&1); then
  missing=""
  while IFS= read -r src; do
    b=$(basename "$src")
    [[ -f "$t/.claude/hooks/$b" ]] || missing="$missing $b"
  done < <(find "$HOOKS_SRC" -name '*.sh' -type f)
  if [[ -z "$missing" ]]; then
    ok "profile full copies every template"
  else
    bad "profile full copies every template" "missing:$missing"
  fi
else
  bad "profile full exits 0" "$out"
fi

# --- profile: python-api copies python + common, and nothing else ------------
t=$(target python-api)
if out=$(bash "$SCRIPT" python-api "$t" 2>&1); then
  want="py-check.sh ruff-fix.sh py-guard.sh migration-guard.sh \
        secret-scan.sh semgrep-guard.sh grype-guard.sh sh-check.sh check-tools.sh"
  unwant="gosec-guard.sh govulncheck-guard.sh ts-fix.sh ts-guard.sh \
          yaml-validate.sh placeholder-guard.sh checkov-guard.sh"
  probs=""
  for w in $want;   do [[ -f "$t/.claude/hooks/$w" ]] || probs="$probs missing:$w"; done
  for u in $unwant; do [[ -f "$t/.claude/hooks/$u" ]] && probs="$probs leaked:$u"; done
  if [[ -z "$probs" ]]; then
    ok "profile python-api copies python + common only"
  else
    bad "profile python-api copies python + common only" "$probs"
  fi
else
  bad "profile python-api exits 0" "$out"
fi

# --- profile: go-api does not pull in python or k8s -------------------------
t=$(target go-api)
if bash "$SCRIPT" go-api "$t" >/dev/null 2>&1; then
  if [[ -f "$t/.claude/hooks/gosec-guard.sh" && -f "$t/.claude/hooks/sh-check.sh" \
        && ! -f "$t/.claude/hooks/ruff-fix.sh" && ! -f "$t/.claude/hooks/checkov-guard.sh" ]]; then
    ok "profile go-api copies go + common only"
  else
    bad "profile go-api copies go + common only" "$(ls "$t/.claude/hooks" | tr '\n' ' ')"
  fi
else
  bad "profile go-api exits 0" "see output"
fi

# --- copied hooks are executable --------------------------------------------
t=$(target execbit)
bash "$SCRIPT" full "$t" >/dev/null 2>&1
notexec=""
for f in "$t"/.claude/hooks/*.sh; do
  [[ -x "$f" ]] || notexec="$notexec $(basename "$f")"
done
if [[ -z "$notexec" ]]; then
  ok "copied hooks are executable"
else
  bad "copied hooks are executable" "not executable:$notexec"
fi

# --- copied hooks are byte-identical to the templates ------------------------
t=$(target fidelity)
bash "$SCRIPT" full "$t" >/dev/null 2>&1
drift=""
while IFS= read -r src; do
  b=$(basename "$src")
  cmp -s "$src" "$t/.claude/hooks/$b" || drift="$drift $b"
done < <(find "$HOOKS_SRC" -name '*.sh' -type f)
if [[ -z "$drift" ]]; then
  ok "copied hooks match templates byte-for-byte"
else
  bad "copied hooks match templates byte-for-byte" "differ:$drift"
fi

# --- settings.json is created with the deny rules ---------------------------
t=$(target settings)
bash "$SCRIPT" full "$t" >/dev/null 2>&1
s="$t/.claude/settings.json"
if [[ -f "$s" ]] && python3 -c "
import json, sys
d = json.load(open('$s'))
deny = d['permissions']['deny']
assert any('push --force' in x for x in deny), 'no force-push deny'
assert any('.env' in x for x in deny), 'no .env deny'
" 2>/dev/null; then
  ok "settings.json written with deny rules"
else
  bad "settings.json written with deny rules" "missing or malformed"
fi

# --- idempotence: a second run preserves local edits unless FORCE=1 ---------
t=$(target rerun)
bash "$SCRIPT" full "$t" >/dev/null 2>&1
echo "# locally customised" >> "$t/.claude/hooks/sh-check.sh"
before=$(cat "$t/.claude/hooks/sh-check.sh")
bash "$SCRIPT" full "$t" >/dev/null 2>&1
if [[ "$(cat "$t/.claude/hooks/sh-check.sh")" == "$before" ]]; then
  ok "re-run preserves an edited hook"
else
  bad "re-run preserves an edited hook" "hook was overwritten without FORCE=1"
fi

if FORCE=1 bash "$SCRIPT" full "$t" >/dev/null 2>&1 \
   && ! grep -q 'locally customised' "$t/.claude/hooks/sh-check.sh"; then
  ok "FORCE=1 overwrites an edited hook"
else
  bad "FORCE=1 overwrites an edited hook" "edit survived FORCE=1"
fi

# --- settings.json is likewise preserved without FORCE ----------------------
t=$(target keepsettings)
bash "$SCRIPT" full "$t" >/dev/null 2>&1
echo '{"permissions":{"deny":["Bash(rm -rf /*)"]}}' > "$t/.claude/settings.json"
bash "$SCRIPT" full "$t" >/dev/null 2>&1
if grep -q 'rm -rf' "$t/.claude/settings.json"; then
  ok "re-run preserves an edited settings.json"
else
  bad "re-run preserves an edited settings.json" "settings.json was clobbered"
fi

# --- argument handling ------------------------------------------------------
code=0; bash "$SCRIPT" >/dev/null 2>&1 || code=$?
if [[ "$code" -eq 1 ]]; then
  ok "no profile exits 1 with usage"
else
  bad "no profile exits 1 with usage" "got exit $code"
fi

code=0; bash "$SCRIPT" full "$TMPDIR/does-not-exist" >/dev/null 2>&1 || code=$?
if [[ "$code" -eq 1 ]]; then
  ok "missing target dir exits 1"
else
  bad "missing target dir exits 1" "got exit $code"
fi

# --- the script must not write outside its target --------------------------
t=$(target confined)
bash "$SCRIPT" full "$t" >/dev/null 2>&1
if [[ "$(find "$t" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" == "1" \
      && -d "$t/.claude" ]]; then
  ok "writes only under <target>/.claude"
else
  bad "writes only under <target>/.claude" "$(find "$t" -mindepth 1 -maxdepth 1 | tr '\n' ' ')"
fi

echo ""
echo "test_init_repo: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
