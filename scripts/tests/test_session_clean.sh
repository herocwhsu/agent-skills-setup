#!/usr/bin/env bash
# Tests for scripts/session-clean.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_DIR/scripts/session-clean.sh"
[[ -f "$SCRIPT" ]] || { echo "FAIL: script not found at $SCRIPT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# Helper to build a clean fixture with valid state layer and clean workspace
fixture_repo() {
  local d="$TMP/$1"
  mkdir -p "$d/.claude/hooks" "$d/scripts"
  echo '{"features": []}' > "$d/feature_list.json"
  echo '# progress' > "$d/PROGRESS.md"
  echo '#!/usr/bin/env bash' > "$d/init.sh"

  # Copy guards
  cp "$REPO_DIR/harness/guards/clean-state-guard.sh" "$d/.claude/hooks/"
  cp "$REPO_DIR/harness/guards/state-layer-guard.sh" "$d/.claude/hooks/"
  cp "$REPO_DIR/scripts/state_layer_check.py" "$d/scripts/"
  chmod +x "$d/.claude/hooks/"*.sh
  git -C "$d" init -q
  git -C "$d" add .
  git -C "$d" -c user.name="Test" -c user.email="test@example.com" commit -qm "init"
  echo "$d"
}

# --- 1. Clean fixture passes with clean handoff banner ------------------------
d=$(fixture_repo "clean")
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "ALL INVARIANTS SATISFIED" ]] \
  && ok "clean fixture passes with clean handoff banner" \
  || bad "clean fixture passes with clean handoff banner" "exit $status, out: $out"

# --- 2. --check mode passes without purging ----------------------------------
d=$(fixture_repo "check_mode")
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" --check 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "Read-only check mode" ]] \
  && ok "--check mode passes without purging" \
  || bad "--check mode passes without purging" "exit $status, out: $out"

# --- 2b. --dry-run alias passes without purging -------------------------------
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" --dry-run 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "Read-only check mode" ]] \
  && ok "--dry-run mode passes without purging" \
  || bad "--dry-run mode passes without purging" "exit $status, out: $out"

# --- 3. Purges __pycache__ and cache dirs ------------------------------------
d=$(fixture_repo "cache_test")
mkdir -p "$d/src/__pycache__" "$d/.pytest_cache"
echo "cache" > "$d/src/__pycache__/app.cpython-314.pyc"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && ! -d "$d/src/__pycache__" && ! -d "$d/.pytest_cache" ]] \
  && ok "purges __pycache__ and .pytest_cache" \
  || bad "purges __pycache__ and .pytest_cache" "exit $status, caches still present"

# --- 4. Dirty workspace with scratch file exits 2 -----------------------------
d=$(fixture_repo "dirty_test")
echo "scratch code" > "$d/scratch.py"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 2 && "$out" =~ "Invariant 4 Violated" ]] \
  && ok "dirty workspace with scratch file exits 2" \
  || bad "dirty workspace with scratch file exits 2" "exit $status, out: $out"

# --- 5. Idempotent: running repeatedly produces exit 0 ------------------------
d=$(fixture_repo "idempotent_test")
status1=0; status2=0
SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" >/dev/null 2>&1 || status1=$?
SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" >/dev/null 2>&1 || status2=$?
[[ $status1 -eq 0 && $status2 -eq 0 ]] \
  && ok "idempotent repeated execution passes exit 0" \
  || bad "idempotent repeated execution passes exit 0" "run1: $status1, run2: $status2"

# --- 6. Unknown argument exits 2 ---------------------------------------------
d=$(fixture_repo "bad_arg")
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" --bogus 2>&1); status=$?; set -e
[[ $status -eq 2 && "$out" =~ "Unknown option" ]] \
  && ok "unknown option exits 2" \
  || bad "unknown option exits 2" "exit $status, out: $out"

# --- 7. Triggers session telemetry trace when trace-evaluation.sh exists -----
d=$(fixture_repo "telemetry_test")
mkdir -p "$d/scripts"
cat <<'SH' > "$d/scripts/trace-evaluation.sh"
#!/usr/bin/env bash
if [[ "${1:-}" == "--trend" ]]; then
  echo "MOCK_TREND_TABLE: Session Telemetry Recorded"
elif [[ "${1:-}" == "--check-thresholds" ]]; then
  echo "OK: thresholds clean"
else
  echo "MOCK_TRACE_RECORDED"
fi
exit 0
SH
chmod +x "$d/scripts/trace-evaluation.sh"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "MOCK_TREND_TABLE: Session Telemetry Recorded" ]] \
  && ok "triggers session telemetry trace and trend display" \
  || bad "triggers session telemetry trace and trend display" "exit $status, out: $out"

# --- 8. Records a run telemetry entry for the current session; failure never blocks ---
d=$(fixture_repo "run_telemetry_test")
cat <<'PY' > "$d/scripts/run_telemetry.py"
import sys
print("MOCK_RUN_TELEMETRY " + " ".join(sys.argv[1:]))
PY
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "MOCK_RUN_TELEMETRY --current-session --out-dir" ]] \
  && ok "records a run telemetry entry for the current session" \
  || bad "records a run telemetry entry for the current session" "exit $status, out: $out"

d=$(fixture_repo "run_telemetry_fail")
printf 'import sys\nsys.exit(2)\n' > "$d/scripts/run_telemetry.py"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "ALL INVARIANTS SATISFIED" && "$out" =~ "not recorded" ]] \
  && ok "a failing run telemetry step is reported but does not block handoff" \
  || bad "a failing run telemetry step is reported but does not block handoff" "exit $status, out: $out"

d=$(fixture_repo "run_telemetry_check_only")
cat <<'PY' > "$d/scripts/run_telemetry.py"
print("MOCK_RUN_TELEMETRY")
PY
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" --check 2>&1); status=$?; set -e
[[ $status -eq 0 && ! "$out" =~ "MOCK_RUN_TELEMETRY" ]] \
  && ok "--check mode does not record run telemetry" \
  || bad "--check mode does not record run telemetry" "exit $status, out: $out"

# --- 9. Attaches feature run summaries; failure never blocks; --check does not run it ---
d=$(fixture_repo "feature_record_test")
cat <<'PY' > "$d/scripts/feature_run_record.py"
import sys
print("MOCK_FEATURE_RECORD " + " ".join(sys.argv[1:]))
PY
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "MOCK_FEATURE_RECORD --repo" && "$out" =~ "--pending --archive" ]] \
  && ok "attaches feature run summaries and archives to budget" \
  || bad "attaches feature run summaries and archives to budget" "exit $status, out: $out"

d=$(fixture_repo "feature_record_fail")
printf 'import sys\nsys.exit(2)\n' > "$d/scripts/feature_run_record.py"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "ALL INVARIANTS SATISFIED" && "$out" =~ "Feature run summaries not recorded" ]] \
  && ok "a failing feature record step is reported but does not block handoff" \
  || bad "a failing feature record step is reported but does not block handoff" "exit $status, out: $out"

d=$(fixture_repo "feature_record_check_only")
printf 'print("MOCK_FEATURE_RECORD")\n' > "$d/scripts/feature_run_record.py"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" --check 2>&1); status=$?; set -e
[[ $status -eq 0 && ! "$out" =~ "MOCK_FEATURE_RECORD" ]] \
  && ok "--check mode does not touch feature records" \
  || bad "--check mode does not touch feature records" "exit $status, out: $out"

# --- 9. An uncommitted completion warns loudly and writes no run record ---
d=$(fixture_repo "uncommitted_completion")
printf 'print("feat-9: completion not committed")\n' > "$d/scripts/feature_run_record.py"
printf 'print("MOCK_RUN_TELEMETRY")\n' > "$d/scripts/run_telemetry.py"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "not committed yet" && ! "$out" =~ "MOCK_RUN_TELEMETRY" ]] \
  && ok "an uncommitted completion warns and skips the run record" \
  || bad "an uncommitted completion warns and skips the run record" "exit $status, out: $out"

d=$(fixture_repo "committed_completion")
printf 'print("feat-9: recorded")\n' > "$d/scripts/feature_run_record.py"
printf 'print("MOCK_RUN_TELEMETRY")\n' > "$d/scripts/run_telemetry.py"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "feat-9: recorded" && "$out" =~ "MOCK_RUN_TELEMETRY" && ! "$out" =~ "not committed yet" ]] \
  && ok "a committed completion still records the run" \
  || bad "a committed completion still records the run" "exit $status, out: $out"

# --- 10. The gate runs log follows HARNESS_VERIFY_LAST_REPORT; empty means no log ---
d=$(fixture_repo "gate_log_env")
printf 'import sys\nprint("MOCK_RUN_TELEMETRY " + " ".join(sys.argv[1:]))\n' > "$d/scripts/run_telemetry.py"
set +e; out=$(HARNESS_VERIFY_LAST_REPORT="$TMP/custom/last.json" SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "--gate-runs-log $TMP/custom/harness-verify-runs.jsonl" ]] \
  && ok "the gate runs log sits next to a custom report path" \
  || bad "the gate runs log sits next to a custom report path" "exit $status, out: $out"
set +e; out=$(HARNESS_VERIFY_LAST_REPORT="" SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "MOCK_RUN_TELEMETRY" && ! "$out" =~ "--gate-runs-log" ]] \
  && ok "an empty HARNESS_VERIFY_LAST_REPORT passes no gate runs log" \
  || bad "an empty HARNESS_VERIFY_LAST_REPORT passes no gate runs log" "exit $status, out: $out"

# --- 11. Only a status line ending in the status counts, not the phrase anywhere in the output ---
d=$(fixture_repo "phrase_in_prose")
printf 'print("note: a completion not committed yet is explained in the docs")\nprint("feat-9: recorded")\n' > "$d/scripts/feature_run_record.py"
printf 'print("MOCK_RUN_TELEMETRY")\n' > "$d/scripts/run_telemetry.py"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "MOCK_RUN_TELEMETRY" && ! "$out" =~ "not committed yet, so" ]] \
  && ok "the phrase inside other text does not skip the run record" \
  || bad "the phrase inside other text does not skip the run record" "exit $status, out: $out"

echo ""
echo "test_session_clean: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
