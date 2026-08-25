#!/usr/bin/env bash
# test_harness_verify.sh — tests for scripts/harness-verify.sh
#
# Uses stub gates via HARNESS_HOOKS_DIR. The real gates cannot be exercised from
# here: tests-guard.sh runs run-tests.sh, which runs this file, so calling the
# script with its default hooks dir would recurse until the process table filled.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/harness-verify.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# stub_gates <registry_exit> <tests_exit> <secret_exit> [types_exit]
stub_gates() {
  local d="$TMPDIR/hooks"
  rm -rf "$d"; mkdir -p "$d"
  printf '#!/usr/bin/env bash\necho "registry says hi"\nexit %s\n' "$1" > "$d/registry-guard.sh"
  printf '#!/usr/bin/env bash\necho "a test failed loudly"\nexit %s\n' "$2" > "$d/tests-guard.sh"
  printf '#!/usr/bin/env bash\necho "scanning"\nexit %s\n'          "$3" > "$d/secret-scan.sh"
  printf '#!/usr/bin/env bash\necho "typing"\nexit %s\n'       "${4:-0}" > "$d/types-guard.sh"
  echo "$d"
}

run_hv() { HARNESS_HOOKS_DIR="$1" bash "$SCRIPT" 2>&1; }

# --- all gates pass -> exit 0 ---
d=$(stub_gates 0 0 0)
out=$(run_hv "$d"); code=$?
if [[ $code -eq 0 ]] && grep -q 'All gates passed' <<<"$out"; then
  ok "all gates passing exits 0"
else
  bad "all gates passing exits 0" "exit $code, out: $out"
fi

# --- every gate is reported OK ---
missing=""
for g in registry types tests "secret scan"; do
  grep -qE "OK +$g" <<<"$out" || missing="$missing $g"
done
[[ -z "$missing" ]] && ok "each gate reported OK" || bad "each gate reported OK" "absent:$missing"

# --- one gate fails -> exit 1, named, and its output shown ---
d=$(stub_gates 0 2 0)
code=0; out=$(run_hv "$d") || code=$?
if [[ $code -eq 1 ]]; then
  ok "a failing gate exits 1"
else
  bad "a failing gate exits 1" "got exit $code"
fi
grep -q 'FAILED: tests' <<<"$out" \
  && ok "failing gate is named in the summary" \
  || bad "failing gate is named in the summary" "out: $out"
grep -q 'a test failed loudly' <<<"$out" \
  && ok "failing gate output is surfaced" \
  || bad "failing gate output is surfaced" "gate stdout was swallowed"

# --- a later gate still runs after an earlier one fails ---
# Aborting on first failure would hide the other gates' verdicts.
grep -qE 'OK +secret scan' <<<"$out" \
  && ok "gates after a failure still run" \
  || bad "gates after a failure still run" "secret scan did not run"

# --- multiple failures are all reported ---
d=$(stub_gates 2 2 0)
code=0; out=$(run_hv "$d") || code=$?
if [[ $code -eq 1 ]] && grep -q 'registry' <<<"$out" && grep -q 'tests' <<<"$out"; then
  ok "multiple failures all reported"
else
  bad "multiple failures all reported" "exit $code, out: $out"
fi

# --- a missing gate script skips rather than failing ---
d=$(stub_gates 0 0 0); rm -f "$d/secret-scan.sh"
code=0; out=$(run_hv "$d") || code=$?
if [[ $code -eq 0 ]] && grep -qE 'SKIP +secret scan' <<<"$out"; then
  ok "missing gate script skips, does not fail"
else
  bad "missing gate script skips" "exit $code, out: $out"
fi

# --- exit 1, not 2: this is a CLI, not a hook ---
d=$(stub_gates 0 1 0)
code=0; run_hv "$d" >/dev/null 2>&1 || code=$?
if [[ $code -eq 1 ]]; then
  ok "reports failure as exit 1 (CLI convention, not a hook's 2)"
else
  bad "reports failure as exit 1" "got $code"
fi

# --- default hooks dir points at the repo's real gates ---
grep -q 'HARNESS_HOOKS_DIR:-$REPO_DIR/.claude/hooks' "$SCRIPT" \
  && ok "defaults to the repo's .claude/hooks" \
  || bad "defaults to the repo's .claude/hooks" "default seam changed"

# --- it delegates rather than reimplementing the checks ---
# Duplicated logic here would drift from the Stop hooks silently.
# Strip comments first: the script's own header explains that tests-guard.sh runs
# run-tests.sh, and grepping the whole file matches that prose rather than code.
if ! grep -vE '^[[:space:]]*#' "$SCRIPT" \
     | grep -qE 'validate-registry|run-tests\.sh|gitleaks|osv-scanner'; then
  ok "delegates to hooks instead of reimplementing gates"
else
  bad "delegates to hooks instead of reimplementing gates" "script calls a checker directly"
fi

# --- every gate in .claude/hooks that is a *-guard or scan runs here ---
# A hook can be registered in settings.json yet missing from this script, in
# which case an on-demand verify silently checks less than a Stop does.
HOOKS_REAL="$SCRIPT_DIR/../.claude/hooks"
unrun=""
for h in "$HOOKS_REAL"/*-guard.sh "$HOOKS_REAL"/secret-scan.sh; do
  [[ -f "$h" ]] || continue
  b=$(basename "$h")
  # PostToolUse/PreToolUse hooks are per-edit, not whole-repo gates.
  case "$b" in sh-check.sh|py-check.sh|precommit-sh-check.sh) continue ;; esac
  grep -q "$b" "$SCRIPT" || unrun="$unrun $b"
done
[[ -z "$unrun" ]] \
  && ok "every whole-repo gate is wired into harness-verify" \
  || bad "every whole-repo gate is wired into harness-verify" "not run:$unrun"

echo ""
echo "test_harness_verify: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
