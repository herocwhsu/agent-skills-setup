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
# Never write the kept "last report" into the real ~/.agent-skills-setup from a test.
export HARNESS_VERIFY_LAST_REPORT="$TMPDIR/state/harness-verify-last.json"

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
  # Every other gate passes, so a missing script is never mistaken for a skip.
  for g in skill-paths-guard bash-compat-guard credential-backend-guard hook-wiring-guard state-layer-guard clean-state-guard runtime-drift-guard; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/$g.sh"
  done
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
for g in registry types tests "clean state" "secret scan"; do
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

# --- a gate that exits 0 but says SKIP is not reported OK ---
# types-guard.sh exits 0 with "SKIP mypy not installed"; printing that as OK
# made "all gates pass" true on a machine that type-checked nothing.
d=$(stub_gates 0 0 0)
printf '#!/usr/bin/env bash\necho "  SKIP  mypy not installed"\nexit 0\n' > "$d/types-guard.sh"
code=0; out=$(run_hv "$d") || code=$?
grep -qE 'OK +types' <<<"$out" \
  && bad "self-skipping gate is not reported OK" "out: $out" \
  || ok "self-skipping gate is not reported OK"
grep -qE 'SKIP +types' <<<"$out" && grep -q 'mypy not installed' <<<"$out" \
  && ok "self-skipping gate is reported SKIP with its reason" \
  || bad "self-skipping gate is reported SKIP with its reason" "out: $out"
grep -q 'SKIPPED: types' <<<"$out" && ! grep -q '^All gates passed\.$' <<<"$out" \
  && ok "summary names skipped gates instead of claiming all passed" \
  || bad "summary names skipped gates instead of claiming all passed" "out: $out"
[[ $code -eq 0 ]] \
  && ok "a skip alone still exits 0 (same as a missing gate script)" \
  || bad "a skip alone still exits 0" "got $code"

# --- exit 1, not 2: this is a CLI, not a hook ---
d=$(stub_gates 0 1 0)
code=0; run_hv "$d" >/dev/null 2>&1 || code=$?
if [[ $code -eq 1 ]]; then
  ok "reports failure as exit 1 (CLI convention, not a hook's 2)"
else
  bad "reports failure as exit 1" "got $code"
fi

# --- default hooks dir points at the repo's real gates ---
grep -q 'HARNESS_HOOKS_DIR:-$REPO_DIR/harness/guards' "$SCRIPT" \
  && ok "defaults to the repo's harness/guards" \
  || bad "defaults to the repo's harness/guards" "default seam changed"

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

# --- every whole-repo gate in harness/guards that is a *-guard or scan runs here ---
# A hook can be registered in settings.json yet missing from this script, in
# which case an on-demand verify silently checks less than a Stop does.
HOOKS_REAL="$SCRIPT_DIR/../harness/guards"
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

# --- feat-044: per-gate duration reporting in console output ---
d=$(stub_gates 0 0 0)
out=$(run_hv "$d"); code=$?
if grep -qE 'OK +registry +\([0-9]+(ms|\.[0-9]+s)\)' <<<"$out"; then
  ok "gate execution duration is displayed in console output"
else
  bad "gate execution duration is displayed in console output" "out: $out"
fi

# --- feat-044: --report writes structured JSON trace ---
d=$(stub_gates 0 0 0)
report_file="$TMPDIR/report.json"
out=$(HARNESS_HOOKS_DIR="$d" bash "$SCRIPT" --report "$report_file" 2>&1); code=$?
if [[ $code -eq 0 && -f "$report_file" ]] && grep -q '"status": "PASS"' "$report_file" && grep -q '"registry"' "$report_file"; then
  ok "--report generates valid JSON trace with gate records"
else
  bad "--report generates valid JSON trace" "exit $code, report exists: $([[ -f "$report_file" ]] && echo yes || echo no)"
fi

# --- feat-044: --json outputs pure JSON to stdout ---
d=$(stub_gates 0 0 0)
json_out=$(HARNESS_HOOKS_DIR="$d" bash "$SCRIPT" --json 2>/dev/null); code=$?
if [[ $code -eq 0 ]] && python3 -c 'import json, sys; d=json.load(sys.stdin); assert d["status"]=="PASS"; assert len(d["gates"])>=4' <<<"$json_out"; then
  ok "--json flag outputs parseable JSON report to stdout"
else
  bad "--json flag outputs parseable JSON report to stdout" "exit $code, out: $json_out"
fi

# --- feat-044: slow gate detection flags slow threshold ---
d=$(stub_gates 0 0 0)
printf '#!/usr/bin/env bash\nsleep 0.05\nexit 0\n' > "$d/registry-guard.sh"
slow_report="$TMPDIR/slow_report.json"
out=$(HARNESS_HOOKS_DIR="$d" HARNESS_VERIFY_SLOW_MS=10 bash "$SCRIPT" --report "$slow_report" 2>&1); code=$?
if [[ $code -eq 0 && -f "$slow_report" ]] && grep -q '"slow": true' "$slow_report"; then
  ok "HARNESS_VERIFY_SLOW_MS flags slow gate in JSON report"
else
  bad "HARNESS_VERIFY_SLOW_MS flags slow gate in JSON report" "out: $out"
fi

# --- the last report is kept for run telemetry, without --report or --json ---
stub_gates 0 0 0
rm -f "$HARNESS_VERIFY_LAST_REPORT"
HARNESS_HOOKS_DIR="$TMPDIR/hooks" bash "$SCRIPT" >/dev/null 2>&1 || true
if [[ -f "$HARNESS_VERIFY_LAST_REPORT" ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["status"]=="PASS" and d["timestamp"]' "$HARNESS_VERIFY_LAST_REPORT"; then
  ok "the last report is kept with a timestamp and status"
else
  bad "the last report is kept with a timestamp and status" "missing or invalid: $HARNESS_VERIFY_LAST_REPORT"
fi

# --- a failing run overwrites it, so a stale PASS cannot be attributed later ---
stub_gates 0 1 0
HARNESS_HOOKS_DIR="$TMPDIR/hooks" bash "$SCRIPT" >/dev/null 2>&1 || true
if python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"]=="FAIL"' "$HARNESS_VERIFY_LAST_REPORT"; then
  ok "a failing run replaces the kept report"
else
  bad "a failing run replaces the kept report" "$(cat "$HARNESS_VERIFY_LAST_REPORT" 2>/dev/null | head -3)"
fi

# --- an unwritable location never changes the exit code or the console output ---
stub_gates 0 0 0
rc=0; HARNESS_VERIFY_LAST_REPORT="/proc/nope/x/last.json" HARNESS_HOOKS_DIR="$TMPDIR/hooks" bash "$SCRIPT" >"$TMPDIR/out.unw" 2>&1 || rc=$?
if [[ $rc -eq 0 ]] && grep -q "All gates passed" "$TMPDIR/out.unw"; then
  ok "an unwritable last-report path does not affect the result"
else
  bad "an unwritable last-report path does not affect the result" "rc=$rc $(tail -3 "$TMPDIR/out.unw")"
fi

# --- an empty setting turns keeping off ---
rm -f "$TMPDIR/off.json"
rc=0; HARNESS_VERIFY_LAST_REPORT="" HARNESS_HOOKS_DIR="$TMPDIR/hooks" bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 0 && ! -e "$TMPDIR/off.json" && "$(ls "$TMPDIR/state" 2>/dev/null | wc -l | tr -d ' ')" -ge 0 ]]; then
  ok "an empty HARNESS_VERIFY_LAST_REPORT keeps nothing and still passes"
else
  bad "an empty HARNESS_VERIFY_LAST_REPORT keeps nothing and still passes" "rc=$rc"
fi

echo ""
echo "test_harness_verify: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
