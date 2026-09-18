#!/usr/bin/env bash
# run-tests.sh — run all skill and script tests in the repo
# Usage: bash scripts/run-tests.sh [--fast]
#   --fast  skip integration tests (those gated behind RUN_INTEGRATION=1)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAST=0
[[ "${1:-}" == "--fast" ]] && FAST=1

# Prefer this repo's own venv (built from requirements-dev.txt) so pytest and
# the third-party packages tests import (anthropic, google.generativeai, lxml)
# resolve from a known, scanned manifest rather than whatever happens to be on
# PATH. Falls back to bare python3 only when .venv was never set up at all —
# a .venv directory that DOES exist must be the right interpreter or we fail
# loud, rather than silently running tests against ambient tooling that may
# not even have the packages under test installed.
PYTHON="python3"
VENV_DIR="$REPO_DIR/.venv"
if [[ -d "$VENV_DIR" ]]; then
  VENV_PY="$VENV_DIR/bin/python3"
  if [[ ! -x "$VENV_PY" ]]; then
    echo "ERROR: .venv exists but is missing python3. Rebuild: rm -rf .venv && python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt" >&2
    exit 1
  fi
  if [[ -f "$REPO_DIR/.python-version" ]]; then
    pinned=$(tr -d '[:space:]' < "$REPO_DIR/.python-version")
    actual=$("$VENV_PY" --version 2>&1 | awk '{print $2}')
    if [[ "$actual" != "$pinned" ]]; then
      echo "ERROR: .venv is Python $actual but .python-version pins $pinned — rebuild: rm -rf .venv && python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt" >&2
      exit 1
    fi
  fi
  PYTHON="$VENV_PY"
fi

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
  if out=$("$PYTHON" -m pytest "$f" -q --tb=short 2>&1); then
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
