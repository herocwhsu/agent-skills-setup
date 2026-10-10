#!/usr/bin/env bash
# tests-guard.sh — Stop/SubagentStop hook: block completion if the repo's
# skill/script test suite is failing. Runs the fast subset (--fast skips
# integration tests gated behind RUN_INTEGRATION=1) so it stays quick enough
# to run on every Stop. Exit 2 blocks; exit 0 allows.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

rc=0
if [[ "${HARNESS_VERIFY_ACTIVE:-0}" -eq 1 || "${1:-}" == "--full" ]]; then
  out=$(bash "$REPO_DIR/scripts/run-tests.sh" --fast 2>&1) || rc=$?
else
  out=$(bash "$REPO_DIR/scripts/run-tests.sh" --fast --changed 2>&1) || rc=$?
fi

if [[ $rc -ne 0 ]]; then
  echo "Blocked: test suite is failing:" >&2
  echo "$out" >&2
  exit 2
fi

exit 0
