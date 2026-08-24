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
untested=0

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
for f in "$REPO_DIR/scripts/tests"/test_*.sh; do
  [[ -f "$f" ]] || continue
  run_bash "$f"
done
for f in "$REPO_DIR/.claude/hooks/tests"/test_*.sh; do
  [[ -f "$f" ]] || continue
  run_bash "$f"
done

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

# Coverage check — see scripts/coverage-check.sh. Reported as a warning: this
# suite's exit code tracks test results, so a coverage gap must not abort it.
echo ""
echo "==> Coverage check (code-bearing subcommands without tests)"
coverage_out=$(bash "$REPO_DIR/scripts/coverage-check.sh" "$REPO_DIR/skills" 2>&1) || true
echo "$coverage_out"
untested=$(sed -n 's/^Coverage: \([0-9]\{1,\}\) .*/\1/p' <<<"$coverage_out")
untested=${untested:-0}

echo ""
echo "Results: $pass passed, $fail failed, $skip skipped, $untested code-bearing subcommands without tests"
[[ $fail -eq 0 ]]
