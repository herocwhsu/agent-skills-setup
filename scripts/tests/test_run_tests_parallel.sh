#!/usr/bin/env bash
# Tests for scripts/run-tests.sh parallel execution (RUN_TESTS_JOBS / --jobs).
# Contract: the output lines, their order, the counts and the exit code are the same at any job count.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

make_fixture() {
  local d="$TMP/$1"
  mkdir -p "$d/scripts/tests" "$d/harness/guards/tests" "$d/tests" "$d/skills/demo/tests"
  cp "$REPO_DIR/scripts/run-tests.sh" "$d/scripts/run-tests.sh"
  printf '#!/usr/bin/env bash\necho "Coverage: 0 code-bearing subcommand(s) without tests, 0 prompt-only"\n' > "$d/scripts/coverage-check.sh"
  printf '#!/usr/bin/env bash\nsleep 1\nexit 0\n' > "$d/scripts/tests/test_a_slow.sh"
  printf '#!/usr/bin/env bash\necho "boom detail"\nexit 1\n' > "$d/scripts/tests/test_b_fails.sh"
  printf '#!/usr/bin/env bash\nsleep 1\nexit 0\n' > "$d/scripts/tests/test_c_slow.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/scripts/tests/test_d_fast.sh"
  printf '#!/usr/bin/env bash\nsleep 1\nexit 0\n' > "$d/harness/guards/tests/test_e_slow.sh"
  printf 'def test_ok():\n    assert True\n' > "$d/tests/test_f.py"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/skills/demo/tests/test_g.sh"
  echo "$d"
}

strip() { sed -E 's/[0-9.]+s//g'; }

run_with() {
  local d="$1" jobs="$2" rc=0
  RUN_TESTS_JOBS="$jobs" bash "$d/scripts/run-tests.sh" --fast >"$TMP/out.$jobs" 2>&1 || rc=$?
  echo "$rc" >"$TMP/rc.$jobs"
}

d=$(make_fixture "f1")
run_with "$d" 1
run_with "$d" 4

# --- 1. same lines, same order, same exit code at 1 and 4 jobs -------------------
if diff <(strip <"$TMP/out.1") <(strip <"$TMP/out.4") >/dev/null && [[ "$(cat "$TMP/rc.1")" == "$(cat "$TMP/rc.4")" ]]; then
  ok "output and exit code are identical at 1 and 4 jobs"
else
  bad "output and exit code are identical at 1 and 4 jobs" "$(diff <(strip <"$TMP/out.1") <(strip <"$TMP/out.4") | head -10)"
fi

# --- 2. a failing test is reported with its output and fails the run -------------
if [[ "$(cat "$TMP/rc.4")" == "1" ]] && grep -q "FAIL  .*test_b_fails.sh" "$TMP/out.4" && grep -q "boom detail" "$TMP/out.4"; then
  ok "a failing test shows its output and the run exits 1"
else
  bad "a failing test shows its output and the run exits 1" "rc=$(cat "$TMP/rc.4")"
fi

# --- 3. results appear in the sequential order even when a later test finishes first
order=$(grep -E "^  (PASS|FAIL)" "$TMP/out.4" | sed -E 's#.*/##')
expected=$(printf '%s\n' test_f.py test_a_slow.sh test_b_fails.sh test_c_slow.sh test_d_fast.sh test_e_slow.sh test_g.sh)
if [[ "$order" == "$expected" ]]; then
  ok "results keep the sequential order"
else
  bad "results keep the sequential order" "got: $(echo "$order" | tr '\n' ' ')"
fi

# --- 4. the summary counts match ------------------------------------------------
if grep -q "Results: 6 passed, 1 failed, 0 skipped" "$TMP/out.4"; then
  ok "summary counts are correct"
else
  bad "summary counts are correct" "$(grep Results "$TMP/out.4")"
fi

# --- 5. parallel is actually faster ---------------------------------------------
t0=$(date +%s)
RUN_TESTS_JOBS=1 bash "$d/scripts/run-tests.sh" --fast >/dev/null 2>&1 || true
t1=$(date +%s)
RUN_TESTS_JOBS=4 bash "$d/scripts/run-tests.sh" --fast >/dev/null 2>&1 || true
t2=$(date +%s)
seq_s=$((t1 - t0)); par_s=$((t2 - t1))
if [[ $par_s -lt $seq_s ]]; then
  ok "4 jobs finish sooner than 1 (${par_s}s against ${seq_s}s)"
else
  bad "4 jobs finish sooner than 1" "${par_s}s against ${seq_s}s"
fi

# --- 6. --jobs flag and invalid values -------------------------------------------
rc=0; bash "$d/scripts/run-tests.sh" --fast --jobs 2 >"$TMP/out.flag" 2>&1 || rc=$?
if [[ $rc -eq 1 ]] && grep -q "Results: 6 passed, 1 failed" "$TMP/out.flag"; then
  ok "--jobs N is accepted"
else
  bad "--jobs N is accepted" "rc=$rc"
fi
for v in 0 -1 abc ""; do
  rc=0; RUN_TESTS_JOBS="$v" bash "$d/scripts/run-tests.sh" --fast >"$TMP/out.bad" 2>&1 || rc=$?
  if grep -q "Results: 6 passed, 1 failed" "$TMP/out.bad"; then
    ok "invalid job count '$v' falls back to a working default"
  else
    bad "invalid job count '$v' falls back to a working default" "rc=$rc $(head -3 "$TMP/out.bad")"
  fi
done

# --- 7. a test that reads stdin does not eat the job queue -----------------------
d2=$(make_fixture "f2")
printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$d2/scripts/tests/test_h_reads_stdin.sh"
rc=0; RUN_TESTS_JOBS=4 bash "$d2/scripts/run-tests.sh" --fast >"$TMP/out.stdin" 2>&1 || rc=$?
if grep -q "Results: 7 passed, 1 failed" "$TMP/out.stdin"; then
  ok "a test reading stdin does not swallow other jobs"
else
  bad "a test reading stdin does not swallow other jobs" "$(grep -E 'Results|FAIL' "$TMP/out.stdin")"
fi

# --- 8. a crashed job (killed) is a failure, not a pass ---------------------------
d3=$(make_fixture "f3")
printf '#!/usr/bin/env bash\nkill -9 $$\n' > "$d3/scripts/tests/test_i_killed.sh"
rc=0; RUN_TESTS_JOBS=4 bash "$d3/scripts/run-tests.sh" --fast >"$TMP/out.kill" 2>&1 || rc=$?
if grep -q "FAIL  .*test_i_killed.sh" "$TMP/out.kill" && [[ $rc -eq 1 ]]; then
  ok "a killed test counts as a failure"
else
  bad "a killed test counts as a failure" "rc=$rc $(grep -E 'killed|Results' "$TMP/out.kill")"
fi

# --- 9. --changed (targeted) mode still works and ignores the job setting --------
rc=0; RUN_TESTS_JOBS=4 bash "$REPO_DIR/scripts/run-tests.sh" --help >"$TMP/out.help" 2>&1 || rc=$?
if [[ $rc -eq 0 ]] && grep -q "Usage: run-tests.sh" "$TMP/out.help"; then
  ok "--help still works"
else
  bad "--help still works" "rc=$rc"
fi

# --- 10. a killed test must not abort the runner or print the shell's own diagnostic ---
d4=$(make_fixture "f4")
printf '#!/usr/bin/env bash\nkill -9 $$\n' > "$d4/scripts/tests/test_i_killed.sh"
rc=0; RUN_TESTS_JOBS=4 bash "$d4/scripts/run-tests.sh" --fast >"$TMP/out.k2" 2>"$TMP/err.k2" || rc=$?
if grep -q "Results: 6 passed, 2 failed" "$TMP/out.k2" && [[ ! -s "$TMP/err.k2" ]]; then
  ok "a killed test is reported with the normal summary and no stray stderr"
else
  bad "a killed test is reported with the normal summary and no stray stderr" "rc=$rc out=$(grep Results "$TMP/out.k2") err=$(head -2 "$TMP/err.k2")"
fi

# --- 11. a crashed worker (xargs aborts) still yields a full report and exit 1 -------
d5=$(make_fixture "f5")
printf '#!/usr/bin/env bash\nkill -9 $PPID\n' > "$d5/scripts/tests/test_j_kills_worker.sh"
rc=0; RUN_TESTS_JOBS=2 bash "$d5/scripts/run-tests.sh" --fast >"$TMP/out.w" 2>"$TMP/err.w" || rc=$?
if [[ $rc -eq 1 ]] && grep -q "FAIL  .*test_j_kills_worker.sh" "$TMP/out.w" && grep -q "^Results:" "$TMP/out.w"; then
  ok "a killed worker is reported as a failure with a full summary"
else
  bad "a killed worker is reported as a failure with a full summary" "rc=$rc $(tail -3 "$TMP/out.w")"
fi

# --- 12. --jobs without a numeric value must not swallow the next flag -----------------
d6=$(make_fixture "f6")
printf '#!/usr/bin/env bash\nexit 0\n' > "$d6/skills/demo/tests/test_integration_polish.sh"
rc=0; bash "$d6/scripts/run-tests.sh" --jobs --fast >"$TMP/out.jf" 2>&1 || rc=$?
if grep -q "SKIP  .*integration_polish" "$TMP/out.jf"; then
  ok "--jobs followed by a flag keeps that flag"
else
  bad "--jobs followed by a flag keeps that flag" "$(grep -E 'SKIP|Results' "$TMP/out.jf")"
fi

# --- 13. SIGTERM leaves nothing behind: no queue process and no test keeps running ---
d7=$(make_fixture "f7")
rm -f "$d7"/scripts/tests/test_*.sh "$d7"/harness/guards/tests/*.sh "$d7"/skills/demo/tests/*.sh
for n in 1 2 3 4 5 6; do
  printf '#!/usr/bin/env bash\necho started >> "%s/started.log"\nsleep 30\n' "$TMP" > "$d7/scripts/tests/test_s$n.sh"
done
rm -f "$TMP/started.log"
RUN_TESTS_JOBS=2 bash "$d7/scripts/run-tests.sh" --fast >/dev/null 2>&1 &
rt=$!
sleep 2
kill -TERM "$rt" 2>/dev/null || true
wait "$rt" 2>/dev/null || true
sleep 1
left=$(ps -axo comm,args | awk -v d="$d7" '$1 ~ /(^|\/)bash$/ && index($0, d "/scripts/tests/test_s") {n++} END {print n + 0}')
queue=$(ps -axo comm,args | awk '$1 ~ /(^|\/)xargs$/ && /-P 2/ && /--worker/ {n++} END {print n + 0}')
started=$(wc -l < "$TMP/started.log" 2>/dev/null | tr -d ' ')
if [[ "${left:-0}" -eq 0 && "${queue:-0}" -eq 0 && "${started:-0}" -le 2 ]]; then
  ok "after SIGTERM no queue process or test is left running (${started:-0} began)"
else
  bad "after SIGTERM no queue process or test is left running" "tests left=${left} queue left=${queue} started=${started}"
fi
pkill -f "$d7/scripts/tests" 2>/dev/null || true

echo ""
echo "test_run_tests_parallel: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
