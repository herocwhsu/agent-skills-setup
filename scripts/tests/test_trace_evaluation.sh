#!/usr/bin/env bash
# Tests for scripts/trace_evaluation.py and scripts/trace-evaluation.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PY_SCRIPT="$REPO_DIR/scripts/trace_evaluation.py"
SH_SCRIPT="$REPO_DIR/scripts/trace-evaluation.sh"

[[ -f "$PY_SCRIPT" ]] || { echo "FAIL: script not found at $PY_SCRIPT"; exit 1; }
[[ -f "$SH_SCRIPT" ]] || { echo "FAIL: script not found at $SH_SCRIPT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# Helper to build a clean fixture repo
fixture_repo() {
  local d="$TMP/$1"
  mkdir -p "$d/docs/telemetry" "$d/scripts"
  echo '{"archive_references": [], "features": [{"id": "f1", "status": "completed", "evidence": "ok"}]}' > "$d/feature_list.json"
  echo -e "# Progress\n\nActive: none\n" > "$d/PROGRESS.md"
  git -C "$d" init -q
  git -C "$d" add .
  git -C "$d" -c user.name="Test" -c user.email="test@example.com" commit -qm "init"
  echo "$d"
}

# --- 1. Python script and shell wrapper are executable ------------------------
[[ -x "$SH_SCRIPT" ]] && ok "trace-evaluation.sh is executable" || bad "trace-evaluation.sh is executable" "not +x"

# --- 2. Record creates valid jsonl record -------------------------------------
d=$(fixture_repo "record_test")
trace_out="$d/docs/telemetry/evaluation-trace.jsonl"
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --record "$trace_out" 2>&1); status=$?; set -e
if [[ $status -eq 0 && -f "$trace_out" ]]; then
  line_count=$(wc -l < "$trace_out" | tr -d '[:space:]')
  has_commit=$(grep -c '"commit"' "$trace_out" || true)
  has_tokens=$(grep -c '"total_state_tokens_est"' "$trace_out" || true)
  if [[ "$line_count" -eq 1 && "$has_commit" -eq 1 && "$has_tokens" -eq 1 ]]; then
    ok "record creates valid jsonl snapshot with token estimation"
  else
    bad "record creates valid jsonl snapshot with token estimation" "lines: $line_count, commit: $has_commit, tokens: $has_tokens"
  fi
else
  bad "record creates valid jsonl snapshot with token estimation" "status: $status, out: $out"
fi

# --- 3. Appending multiple records maintains jsonl format ----------------------
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --record "$trace_out" 2>&1); status=$?; set -e
line_count=$(wc -l < "$trace_out" | tr -d '[:space:]' || echo 0)
[[ $status -eq 0 && "$line_count" -eq 2 ]] \
  && ok "subsequent record appends to trace file" \
  || bad "subsequent record appends to trace file" "status: $status, lines: $line_count"

# --- 4. Trend renders formatted history table ----------------------------------
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --trend "$trace_out" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "EVALUATION TRACE HISTORY" && "$out" =~ "Commit" && "$out" =~ "Est. Tokens" ]] \
  && ok "trend outputs formatted history table with token estimates" \
  || bad "trend outputs formatted history table with token estimates" "status: $status, out: $out"

# --- 5. JSON output mode produces valid JSON ----------------------------------
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --json 2>&1); status=$?; set -e
is_json=$(echo "$out" | python3 -c "import json, sys; json.load(sys.stdin); print('VALID')" 2>/dev/null || echo "INVALID")
[[ $status -eq 0 && "$is_json" == "VALID" ]] \
  && ok "--json outputs valid JSON payload" \
  || bad "--json outputs valid JSON payload" "status: $status, out: $out"

# --- 6. Threshold check flags bloated feature_list.json -----------------------
d_bloat=$(fixture_repo "bloat_test")
# Artificially expand feature_list.json beyond 250 lines
python3 -c "
with open('$d_bloat/feature_list.json', 'w') as f:
    f.write('{\n  \"features\": [\n')
    for i in range(260):
        f.write(f'    {{\"id\": \"f{i}\"}},\n')
    f.write('    {\"id\": \"last\"}\n  ]\n}\n')
"
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d_bloat" --check-thresholds 2>&1); status=$?; set -e
[[ $status -ne 0 && "$out" =~ "WARNING" && "$out" =~ "feature_list.json exceeds" ]] \
  && ok "--check-thresholds flags bloated feature_list.json" \
  || bad "--check-thresholds flags bloated feature_list.json" "status: $status, out: $out"

# --- 7. Shell wrapper executes cleanly ----------------------------------------
set +e; out=$(bash "$SH_SCRIPT" --repo-dir "$d" --json 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ '"commit"' ]] \
  && ok "trace-evaluation.sh wrapper works identically" \
  || bad "trace-evaluation.sh wrapper works identically" "status: $status, out: $out"

# --- 8. Agent attribution and duration recorded in snapshot -------------------
trace_agent="$d/docs/telemetry/agent-trace.jsonl"
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --record "$trace_agent" --agent codex --duration-ms 2400 2>&1); status=$?; set -e
has_agent=$(grep -c '"agent": "codex"' "$trace_agent" || true)
has_dur=$(grep -c '"duration_ms": 2400' "$trace_agent" || true)
has_dur_str=$(grep -c '"duration_str": "2.4s"' "$trace_agent" || true)
[[ $status -eq 0 && "$has_agent" -eq 1 && "$has_dur" -eq 1 && "$has_dur_str" -eq 1 ]] \
  && ok "--agent and --duration-ms recorded in snapshot" \
  || bad "--agent and --duration-ms recorded in snapshot" "status: $status, agent: $has_agent, dur: $has_dur"

# --- 9. Trend displays Agent and Spent Time columns ---------------------------
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --trend "$trace_agent" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "Agent" && "$out" =~ "Spent Time" && "$out" =~ "codex" && "$out" =~ "2.4s" ]] \
  && ok "trend table displays Agent and Spent Time columns" \
  || bad "trend table displays Agent and Spent Time columns" "status: $status, out: $out"

# --- Summary ------------------------------------------------------------------
echo ""
echo "test_trace_evaluation.sh: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
