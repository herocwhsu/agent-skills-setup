#!/usr/bin/env bash
# harness-verify.sh — one command that runs every gate this repo enforces.
#
# The same checks already run as Stop hooks, but only when an agent finishes a
# turn. This is the entry point for running them on demand: before a commit,
# after a rebase, or when an agent needs to confirm its work rather than assume
# it. Having one name to invoke is the point — "run the hook scripts"
# is an instruction people and agents skip.
#
# Single source of truth: this delegates to .claude/hooks/*.sh rather than
# re-implementing the checks, so the on-demand path and the Stop path can never
# drift apart.
#
# Observability (feat-044):
# Profiles execution duration per gate and supports structured JSON trace
# telemetry via --json or --report <path> (or HARNESS_VERIFY_REPORT).
#
# Exit 0 = every gate passed. Exit 1 = at least one failed (this is a CLI, not
# a hook; hooks use exit 2 to block).
set -uo pipefail

export HARNESS_VERIFY_ACTIVE=1

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Overridable so tests can point at stub gates. A test cannot exercise the real
# gates: tests-guard.sh runs run-tests.sh, which runs the tests, so a test that
# invoked this script directly would recurse until it ran out of processes.
HOOKS="${HARNESS_HOOKS_DIR:-$REPO_DIR/.claude/hooks}"

# Parse command line options
REPORT_FILE="${HARNESS_VERIFY_REPORT:-}"
JSON_OUT=0
SLOW_THRESHOLD="${HARNESS_VERIFY_SLOW_MS:-5000}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUT=1
      shift
      ;;
    --report)
      REPORT_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: harness-verify.sh [--json] [--report <path>]"
      exit 0
      ;;
    *)
      # Ignore unrecognized positional args for backwards compatibility
      shift
      ;;
  esac
done

now_ms() {
  local ts
  ts=$(date +%s%N 2>/dev/null || true)
  if [[ "$ts" =~ ^[0-9]{13,19}$ ]]; then
    if [[ ${#ts} -eq 19 ]]; then
      echo $(( ts / 1000000 ))
    else
      echo "$ts"
    fi
  else
    python3 -c 'import time; print(int(time.time() * 1000))'
  fi
}

t_verify_start=$(now_ms)
GATE_ENTRIES_FILE=$(mktemp -t harness_verify.XXXXXX 2>/dev/null || mktemp)
trap 'rm -f "$GATE_ENTRIES_FILE"' EXIT

FAILED=""
SKIPPED=""

run_gate() {
  local label="$1" script="$2"
  shift 2
  local t_start t_end duration_ms dur_str
  t_start=$(now_ms)
  if [[ ! -x "$script" && ! -f "$script" ]]; then
    t_end=$(now_ms)
    duration_ms=$(( t_end - t_start ))
    [[ $duration_ms -lt 0 ]] && duration_ms=0
    dur_str="${duration_ms}ms"
    if [[ $JSON_OUT -eq 0 ]]; then
      echo "  SKIP  $label (missing $script) ($dur_str)"
    fi
    SKIPPED="$SKIPPED $label"
    printf '%s\t%s\t%d\t%d\n' "$label" "SKIP" "0" "$duration_ms" >> "$GATE_ENTRIES_FILE"
    return 0
  fi
  local out status
  out=$(bash "$script" "$@" 2>&1)
  status=$?
  t_end=$(now_ms)
  duration_ms=$(( t_end - t_start ))
  [[ $duration_ms -lt 0 ]] && duration_ms=0
  if [[ $duration_ms -ge 1000 ]]; then
    dur_str="$(( duration_ms / 1000 )).$(( (duration_ms % 1000) / 100 ))s"
  else
    dur_str="${duration_ms}ms"
  fi
  if [[ $duration_ms -ge $SLOW_THRESHOLD ]]; then
    dur_str="$dur_str, slow"
  fi

  # A gate whose tool is absent exits 0 and says SKIP. Reporting that as OK made
  # "all gates passed" true on a machine where mypy never ran.
  if [[ $status -eq 0 ]] && grep -qE '^[[:space:]]*SKIP[[:space:]]' <<<"$out"; then
    if [[ $JSON_OUT -eq 0 ]]; then
      echo "  SKIP  $label ($dur_str)"
      grep -E '^[[:space:]]*SKIP[[:space:]]' <<<"$out" | sed 's/^[[:space:]]*SKIP[[:space:]]*/        /'
    fi
    SKIPPED="$SKIPPED $label"
    printf '%s\t%s\t%d\t%d\n' "$label" "SKIP" "0" "$duration_ms" >> "$GATE_ENTRIES_FILE"
  elif [[ $status -eq 0 ]]; then
    if [[ $JSON_OUT -eq 0 ]]; then
      echo "  OK    $label ($dur_str)"
    fi
    printf '%s\t%s\t%d\t%d\n' "$label" "OK" "0" "$duration_ms" >> "$GATE_ENTRIES_FILE"
  else
    if [[ $JSON_OUT -eq 0 ]]; then
      echo "  FAIL  $label (exit $status, $dur_str)"
      printf '%s\n' "$out" | sed 's/^/        /'
    fi
    FAILED="$FAILED $label"
    printf '%s\t%s\t%d\t%d\n' "$label" "FAIL" "$status" "$duration_ms" >> "$GATE_ENTRIES_FILE"
  fi
}

if [[ $JSON_OUT -eq 0 ]]; then
  echo "=== harness verify ==="
fi

run_gate "registry"    "$HOOKS/registry-guard.sh"
run_gate "types"       "$HOOKS/types-guard.sh"
run_gate "tests"       "$HOOKS/tests-guard.sh"
run_gate "skill paths" "$HOOKS/skill-paths-guard.sh"
run_gate "bash compat" "$HOOKS/bash-compat-guard.sh"
run_gate "cred backends" "$HOOKS/credential-backend-guard.sh"
run_gate "hook wiring" "$HOOKS/hook-wiring-guard.sh"
run_gate "state layer" "$HOOKS/state-layer-guard.sh"
run_gate "clean state" "$HOOKS/clean-state-guard.sh"
run_gate "runtime drift" "$HOOKS/runtime-drift-guard.sh"

# Passes the real settings files as well as the tree: a hook wired to a path that
# no longer resolves is invisible to the Stop hook by design, and this is where a
# person asks the question deliberately. A warning, not a gate.
if ! out=$(python3 "$REPO_DIR/scripts/hook-wiring-check.py" "$REPO_DIR" \
           "$HOME/.claude/settings.json" "${CODEX_HOME:-$HOME/.codex}/hooks.json" \
           "${GEMINI_CONFIG_DIR:-$HOME/.gemini/config}/hooks.json" 2>&1); then
  echo "  WARNING: a wired hook path no longer resolves:" >&2
  printf '%s\n' "$out" >&2
fi
run_gate "secret scan" "$HOOKS/secret-scan.sh"

t_verify_end=$(now_ms)
TOTAL_MS=$(( t_verify_end - t_verify_start ))
[[ $TOTAL_MS -lt 0 ]] && TOTAL_MS=0

# Generate JSON report if requested
if [[ -n "$REPORT_FILE" || $JSON_OUT -eq 1 ]]; then
  report_json=$(python3 -c '
import json, sys, time
entries_file, failed, skipped, total_ms, slow_ms = sys.argv[1:6]
gates = []
with open(entries_file) as f:
    for line in f:
        parts = line.strip().split("\t")
        if len(parts) == 4:
            name, status, exit_code, dur = parts
            dur_int = int(dur)
            gates.append({
                "name": name,
                "status": status,
                "exit_code": int(exit_code),
                "duration_ms": dur_int,
                "slow": dur_int >= int(slow_ms),
            })
report = {
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "status": "FAIL" if failed.strip() else ("SKIP" if skipped.strip() else "PASS"),
    "total_duration_ms": int(total_ms),
    "slow_threshold_ms": int(slow_ms),
    "gates": gates,
    "failed": failed.strip().split() if failed.strip() else [],
    "skipped": skipped.strip().split() if skipped.strip() else [],
}
print(json.dumps(report, indent=2))
' "$GATE_ENTRIES_FILE" "$FAILED" "$SKIPPED" "$TOTAL_MS" "$SLOW_THRESHOLD")

  if [[ -n "$REPORT_FILE" ]]; then
    mkdir -p "$(dirname "$REPORT_FILE")"
    printf '%s\n' "$report_json" > "$REPORT_FILE"
  fi
  if [[ $JSON_OUT -eq 1 ]]; then
    printf '%s\n' "$report_json"
  fi
fi

if [[ $JSON_OUT -eq 0 ]]; then
  echo ""
  if [[ -n "$FAILED" ]]; then
    echo "FAILED:$FAILED"
    [[ -n "$SKIPPED" ]] && echo "SKIPPED:$SKIPPED"
    exit 1
  fi
  if [[ -n "$SKIPPED" ]]; then
    echo "Passed, but SKIPPED:$SKIPPED (those gates checked nothing)."
    exit 0
  fi
  echo "All gates passed."
  exit 0
else
  if [[ -n "$FAILED" ]]; then
    exit 1
  fi
  exit 0
fi
