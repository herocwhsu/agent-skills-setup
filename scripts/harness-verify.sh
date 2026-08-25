#!/usr/bin/env bash
# harness-verify.sh — one command that runs every gate this repo enforces.
#
# The same checks already run as Stop hooks, but only when an agent finishes a
# turn. This is the entry point for running them on demand: before a commit,
# after a rebase, or when an agent needs to confirm its work rather than assume
# it. Having one name to invoke is the point — "run the three hook scripts"
# is an instruction people and agents skip.
#
# Single source of truth: this delegates to .claude/hooks/*.sh rather than
# re-implementing the checks, so the on-demand path and the Stop path can never
# drift apart.
#
# Exit 0 = every gate passed. Exit 1 = at least one failed (this is a CLI, not
# a hook; hooks use exit 2 to block).
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Overridable so tests can point at stub gates. A test cannot exercise the real
# gates: tests-guard.sh runs run-tests.sh, which runs the tests, so a test that
# invoked this script directly would recurse until it ran out of processes.
HOOKS="${HARNESS_HOOKS_DIR:-$REPO_DIR/.claude/hooks}"

FAILED=""
run_gate() {
  local label="$1" script="$2"
  shift 2
  if [[ ! -x "$script" && ! -f "$script" ]]; then
    echo "  SKIP  $label (missing $script)"
    return 0
  fi
  local out status
  out=$(bash "$script" "$@" 2>&1)
  status=$?
  if [[ $status -eq 0 ]]; then
    echo "  OK    $label"
  else
    echo "  FAIL  $label (exit $status)"
    printf '%s\n' "$out" | sed 's/^/        /'
    FAILED="$FAILED $label"
  fi
}

echo "=== harness verify ==="
run_gate "registry"    "$HOOKS/registry-guard.sh"
run_gate "types"       "$HOOKS/types-guard.sh"
run_gate "tests"       "$HOOKS/tests-guard.sh"
run_gate "secret scan" "$HOOKS/secret-scan.sh"

echo ""
if [[ -n "$FAILED" ]]; then
  echo "FAILED:$FAILED"
  exit 1
fi
echo "All gates passed."
exit 0
