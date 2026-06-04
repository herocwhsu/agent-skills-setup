#!/usr/bin/env bash
# run-tests.sh — run all skill and script tests in the repo
# Usage: bash scripts/run-tests.sh [--fast]
#   --fast  skip integration tests (those gated behind RUN_INTEGRATION=1)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAST=0
[[ "${1:-}" == "--fast" ]] && FAST=1

pass=0
fail=0
skip=0

run_bash() {
  local f="$1"
  local out
  if out=$(bash "$f" 2>&1); then
    echo "  PASS  $f"
    pass=$((pass + 1))
  else
    echo "  FAIL  $f"
    echo "$out" | sed 's/^/        /'
    fail=$((fail + 1))
  fi
}

run_python() {
  local f="$1"
  local out
  if out=$(python3 -m pytest "$f" -q --tb=short 2>&1); then
    echo "  PASS  $f"
    pass=$((pass + 1))
  else
    echo "  FAIL  $f"
    echo "$out" | sed 's/^/        /'
    fail=$((fail + 1))
  fi
}

echo "==> Script tests"
if [[ -d "$REPO_DIR/tests" ]]; then
  for f in "$REPO_DIR/tests"/*.py; do
    [[ -f "$f" ]] || continue
    run_python "$f"
  done
fi

echo ""
echo "==> Skill tests"
while IFS= read -r -d '' f; do
  case "$f" in
    *integration_polish.sh)
      if [[ $FAST -eq 1 ]]; then
        echo "  SKIP  $f  (integration — use RUN_INTEGRATION=1 to run)"
        skip=$((skip + 1))
        continue
      fi
      ;;
  esac
  case "$f" in
    *.sh) run_bash "$f" ;;
    *.py) run_python "$f" ;;
  esac
done < <(find "$REPO_DIR/skills" -type f \( -name "test_*.sh" -o -name "test_*.py" \) -print0 | sort -z)

echo ""
echo "Results: $pass passed, $fail failed, $skip skipped"
[[ $fail -eq 0 ]]
