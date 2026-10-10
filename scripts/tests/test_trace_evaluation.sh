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

# --- 10. Auto duration delta calculated when --duration-ms omitted ------------
# Add a record with recent past timestamp (within 30m session window), then record again without --duration-ms
trace_auto="$d/docs/telemetry/auto-trace.jsonl"
recent_ts=$(python3 -c "import datetime as _dt; UTC = getattr(_dt, 'UTC', _dt.timezone.utc); print((_dt.datetime.now(UTC) - _dt.timedelta(seconds=120)).isoformat())")
echo "{\"commit\": \"init\", \"timestamp\": \"$recent_ts\", \"agent\": \"claude\", \"duration_ms\": 1000, \"duration_str\": \"1.0s\", \"state_layer\": {}, \"test_metrics\": {}, \"thresholds\": {\"status\": \"OK\", \"warnings\": []}}" > "$trace_auto"
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --record "$trace_auto" 2>&1); status=$?; set -e
second_line=$(tail -n 1 "$trace_auto")
has_auto_dur=$(echo "$second_line" | python3 -c "import json, sys; d=json.load(sys.stdin); print('VALID' if d.get('duration_ms', 0) > 0 and d.get('duration_str') != '-' else 'INVALID')" 2>/dev/null || echo "ERROR")
[[ $status -eq 0 && "$has_auto_dur" == "VALID" ]] \
  && ok "auto duration delta calculated when --duration-ms is omitted" \
  || bad "auto duration delta calculated when --duration-ms is omitted" "status: $status, auto_dur: $has_auto_dur, out: $out"

# --- 11. Markdown dashboard generated on record and viewable via --markdown ---
summary_md="$d/docs/telemetry/SUMMARY.md"
[[ -f "$summary_md" ]] && grep -q "Repository Evaluation & Telemetry Dashboard" "$summary_md" \
  && ok "SUMMARY.md markdown dashboard generated automatically on record" \
  || bad "SUMMARY.md markdown dashboard generated automatically on record" "file missing or invalid header"

set +e; md_out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --markdown "$trace_auto" 2>&1); md_status=$?; set -e
[[ $md_status -eq 0 && "$md_out" =~ "| Commit |" && "$md_out" =~ "Status" ]] \
  && ok "--markdown renders formatted markdown table" \
  || bad "--markdown renders formatted markdown table" "status: $md_status, out: $md_out"

# --- 13. Subagents tracking via CLI and trend rendering -----------------------
trace_sub="$d/docs/telemetry/sub-trace.jsonl"
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --record "$trace_sub" --self-subagents 7 --outside-subagents claude 2>&1); status=$?; set -e
has_self=$(grep -c '"self_count": 7' "$trace_sub" || true)
has_out=$(grep -c '"outside_used": \["claude"\]' "$trace_sub" || true)
has_indep=$(grep -c '"independent_verified": true' "$trace_sub" || true)
set +e; trend_sub=$(python3 "$PY_SCRIPT" --repo-dir "$d" --trend "$trace_sub" 2>&1); set -e
[[ $status -eq 0 && "$has_self" -eq 1 && "$has_out" -eq 1 && "$has_indep" -eq 1 && "$trend_sub" =~ "7 self, 1 out (claude)" ]] \
  && ok "--self-subagents and --outside-subagents recorded and rendered in trend" \
  || bad "--self-subagents and --outside-subagents recorded and rendered in trend" "status: $status, trend: $trend_sub"

# --- 14. Auto-detect outside agent runs from outside-agent-runs.jsonl ----------
mkdir -p "$d/docs/telemetry"
now_iso=$(python3 -c "import datetime as _dt; UTC = getattr(_dt, 'UTC', _dt.timezone.utc); print(_dt.datetime.now(UTC).isoformat())")
echo "{\"timestamp\": \"$now_iso\", \"agent\": \"claude\", \"family\": \"claude\", \"purpose\": \"review\", \"caller_family\": \"gemini\", \"exit_code\": 0, \"independent\": true}" > "$d/docs/telemetry/outside-agent-runs.jsonl"
trace_auto_sub="$d/docs/telemetry/auto-sub-trace.jsonl"
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --record "$trace_auto_sub" --self-subagents 2 2>&1); status=$?; set -e
has_auto_out=$(grep -c '"outside_used": \["claude"\]' "$trace_auto_sub" || true)
has_auto_indep=$(grep -c '"independent_verified": true' "$trace_auto_sub" || true)
summary_auto="$d/docs/telemetry/SUMMARY.md"
has_sub_col=$(grep -c "Subagents" "$summary_auto" || true)
has_sub_val=$(grep -c "2 self, 1 out (claude)" "$summary_auto" || true)
[[ $status -eq 0 && "$has_auto_out" -eq 1 && "$has_auto_indep" -eq 1 && "$has_sub_col" -ge 1 && "$has_sub_val" -ge 1 ]] \
  && ok "auto-detects outside agent runs and renders Subagents column in SUMMARY.md" \
  || bad "auto-detects outside agent runs and renders Subagents column in SUMMARY.md" "status: $status, out: $has_auto_out, sub_val: $has_sub_val"

# --- 15. Defensive tolerance against malformed and naive outside runs ---------
trace_corrupt="$d/docs/telemetry/corrupt-sub-trace.jsonl"
naive_now=$(python3 -c "import datetime as _dt; UTC = getattr(_dt, 'UTC', _dt.timezone.utc); print(_dt.datetime.now(UTC).replace(tzinfo=None, microsecond=0).isoformat())")
cat << EOF > "$d/docs/telemetry/outside-agent-runs.jsonl"
not json
123
{"timestamp": 12345}
{"timestamp": "$naive_now", "agent": "claude", "independent": true}
{"timestamp": "invalid_date", "agent": "claude"}
EOF
set +e; out=$(python3 "$PY_SCRIPT" --repo-dir "$d" --record "$trace_corrupt" 2>&1); status=$?; set -e
has_recorded=$(test -f "$trace_corrupt" && echo "YES" || echo "NO")
has_claude_naive=$(grep -c '"outside_used": \["claude"\]' "$trace_corrupt" || true)
fmt_none=$(python3 -c "import sys; from pathlib import Path; sys.path.insert(0, '$REPO_DIR/scripts'); import trace_evaluation as te; print(te.format_subagents({'self_count': None, 'outside_count': None}))")
fmt_with_out=$(python3 -c "import sys; from pathlib import Path; sys.path.insert(0, '$REPO_DIR/scripts'); import trace_evaluation as te; print(te.format_subagents({'self_count': None, 'outside_count': 1, 'outside_used': [None, 'codex']}))")
[[ $status -eq 0 && "$has_recorded" == "YES" && "$has_claude_naive" -eq 1 && "$fmt_none" == "-" && "$fmt_with_out" == "1 out (codex)" ]] \
  && ok "handles malformed, naive, and None subagent telemetry defensively" \
  || bad "handles malformed, naive, and None subagent telemetry defensively" "status: $status, claude: $has_claude_naive, fmt_none: $fmt_none, fmt_out: $fmt_with_out"

# --- 16. Cross-repo isolation in global runtime state fallback ----------------
global_state="$d/mock_global_state"
mkdir -p "$global_state/state"
resolved_d=$(python3 -c "import sys; from pathlib import Path; print(Path(sys.argv[1]).resolve())" "$d")
now_iso=$(python3 -c "import datetime as _dt; UTC = getattr(_dt, 'UTC', _dt.timezone.utc); print(_dt.datetime.now(UTC).isoformat())")
cat << EOF > "$global_state/state/outside-agent-runs.jsonl"
{"timestamp": "$now_iso", "agent": "codex", "independent": true, "repo": "/foreign/unrelated/repo"}
{"timestamp": "$now_iso", "agent": "kiro", "independent": true, "repo": null}
{"timestamp": "$now_iso", "agent": "claude", "independent": true, "repo": "$resolved_d"}
EOF
trace_iso="$d/docs/telemetry/iso-trace.jsonl"
rm -f "$d/docs/telemetry/outside-agent-runs.jsonl"
set +e; out=$(OUTSIDE_AGENT_DIR="$global_state" python3 "$PY_SCRIPT" --repo-dir "$d" --record "$trace_iso" 2>&1); status=$?; set -e
has_claude=$(grep -c '"outside_used": \["claude"\]' "$trace_iso" || true)
has_codex=$(grep -c 'codex' "$trace_iso" || true)
has_kiro=$(grep -c 'kiro' "$trace_iso" || true)
[[ $status -eq 0 && "$has_claude" -eq 1 && "$has_codex" -eq 0 && "$has_kiro" -eq 0 ]] \
  && ok "cross-repo isolation filters out foreign and null repo runs in global fallback" \
  || bad "cross-repo isolation filters out foreign and null repo runs in global fallback" "status: $status, claude: $has_claude, codex: $has_codex, kiro: $has_kiro"

# --- Summary ------------------------------------------------------------------
echo ""
echo "test_trace_evaluation.sh: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
