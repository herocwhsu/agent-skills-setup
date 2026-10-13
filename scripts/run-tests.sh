#!/usr/bin/env bash
# run-tests.sh — run all skill and script tests in the repo
# Usage: bash scripts/run-tests.sh [--fast] [--changed] [--jobs N]
#   --fast     skip integration tests (those gated behind RUN_INTEGRATION=1)
#   --changed  run only the tests that cover changed files
#   --jobs N   run N test files at once (default: RUN_TESTS_JOBS, else min(cpus, 4)).
#              Results print in the same order and with the same counts at any N.
set -euo pipefail

export RUN_TESTS_ACTIVE=1

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAST=0
CHANGED=0
JOBS="${RUN_TESTS_JOBS:-}"
WORKER=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast) FAST=1 ;;
    --changed) CHANGED=1 ;;
    --worker) WORKER=1; break ;;
    --jobs)
      case "${2:-}" in
        ''|*[!0-9]*) ;;
        *) JOBS="$2"; shift ;;
      esac
      ;;
    -h|--help)
      echo "Usage: run-tests.sh [--fast] [--changed] [--jobs N]"
      exit 0
      ;;
  esac
  shift
done
case "$JOBS" in
  ''|*[!0-9]*|0)
    JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    case "$JOBS" in ''|*[!0-9]*|0) JOBS=1 ;; esac
    if [[ $JOBS -gt 4 ]]; then JOBS=4; fi
    ;;
esac

# Prefer this repo's own venv (built from requirements-dev.txt) so pytest and
# the third-party packages tests import (anthropic, google.genai, lxml)
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

if [[ $WORKER -eq 1 ]]; then
  # Internal: run one test file and record its output and exit code. Never fails itself,
  # so the parent can tell a failing test from a broken runner.
  kind="$2"; dir="$3"; f="$4"; outbase="$5"
  # The test runs in a subshell whose stderr is already the output file, so a signal
  # diagnostic from this shell ("Killed: 9 ...") cannot reach the shared stderr.
  rc=0
  {
    case "$kind" in
      bash) bash "$f" ;;
      py) "$PYTHON" -m pytest "$f" -q --tb=short ;;
      pyin) (cd "$dir" && "$PYTHON" -m pytest "$f" -q --tb=short) ;;
    esac
  } </dev/null >"$outbase.out" 2>&1 || rc=$?
  echo "$rc" >"$outbase.rc"
  exit 0
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

run_python_in() {
  local dir="$1" f="$2"
  local out
  if out=$(cd "$dir" && "$PYTHON" -m pytest "$f" -q --tb=short 2>&1); then
    echo "  PASS  $f"
    pass=$((pass + 1))
  else
    echo "  FAIL  $f"
    echo "$out" | sed 's/^/        /'
    fail=$((fail + 1))
  fi
}

if [[ $CHANGED -eq 1 ]]; then
  echo "==> Resolving targeted tests for changed files..."
  changed_files=$(bash "$REPO_DIR/scripts/get-changed-files.sh")
  if [[ -z "$changed_files" ]]; then
    echo "No changed files detected; nothing to test."
    exit 0
  fi
  targets=$(printf '%s\n' "$changed_files" | "$PYTHON" "$REPO_DIR/scripts/resolve_test_targets.py")
  if [[ "$targets" == "ALL" ]]; then
    echo "  Shared infrastructure or unrecognized files changed — executing full suite."
  elif [[ -z "$targets" ]]; then
    echo "  Changes affect non-executable documentation or metadata — no tests required."
    exit 0
  else
    echo "==> Running targeted tests:"
    while IFS= read -r test_file; do
      [[ -z "$test_file" ]] && continue
      abs_f="$REPO_DIR/$test_file"
      [[ -f "$abs_f" ]] || continue
      case "$test_file" in
        *.sh) run_bash "$abs_f" ;;
        *.py)
          case "$test_file" in
            docs/harness-creator/lecture-*/code/*)
              run_python_in "$(dirname "$abs_f")" "$abs_f" ;;
            *)
              run_python "$abs_f" ;;
          esac
          ;;
      esac
    done <<< "$targets"
    echo ""
    echo "Targeted Results: $pass passed, $fail failed, $skip skipped"
    [[ $fail -eq 0 ]]
    exit 0
  fi
fi

# Full run: build the ordered job list, run it N at a time, then report in list order.
JOB_KIND=()
JOB_DIR=()
JOB_FILE=()
add_job() { JOB_KIND+=("$1"); JOB_DIR+=("$2"); JOB_FILE+=("$3"); }

add_job text - "==> Script tests"
if [[ -d "$REPO_DIR/tests" ]]; then
  for f in "$REPO_DIR/tests"/*.py; do
    [[ -f "$f" ]] || continue
    add_job py - "$f"
  done
fi
for f in "$REPO_DIR/scripts/tests"/test_*.sh; do
  [[ -f "$f" ]] || continue
  add_job bash - "$f"
done
HOOK_TESTS_DIR="$REPO_DIR/harness/guards/tests"
[[ -d "$HOOK_TESTS_DIR" ]] || HOOK_TESTS_DIR="$REPO_DIR/.claude/hooks/tests"
for f in "$HOOK_TESTS_DIR"/test_*.sh; do
  [[ -f "$f" ]] || continue
  add_job bash - "$f"
done

add_job text - ""
add_job text - "==> Lecture tests"
# Each lecture's code/ dir is its own import root (tests import their sibling module).
for dir in "$REPO_DIR"/docs/harness-creator/lecture-*/code; do
  for f in "$dir"/test_*.py; do
    [[ -f "$f" ]] || continue
    add_job pyin "$dir" "$f"
  done
done

add_job text - ""
add_job text - "==> Skill tests"
while IFS= read -r -d '' f; do
  case "$f" in
    *integration_polish.sh)
      if [[ $FAST -eq 1 ]]; then
        add_job skip - "$f"
        continue
      fi
      ;;
  esac
  case "$f" in
    *.sh) add_job bash - "$f" ;;
    *.py) add_job py - "$f" ;;
  esac
done < <(find "$REPO_DIR/skills" -type f \( -name "test_*.sh" -o -name "test_*.py" \) -print0 | sort -z)

WORK=$(mktemp -d)
XARGS_PID=""
# Print the process ids below $1, deepest first, so children die before the shell that waits on them.
descendants() {
  local kid
  for kid in $(pgrep -P "$1" 2>/dev/null || true); do
    descendants "$kid"
    echo "$kid"
  done
}
cleanup() {
  if [[ -n "$XARGS_PID" ]]; then
    # Stop the queue first so no new test starts, then everything it already started.
    kill -STOP "$XARGS_PID" 2>/dev/null || true
    # shellcheck disable=SC2046
    kill -TERM $(descendants "$XARGS_PID") "$XARGS_PID" 2>/dev/null || true
    kill -CONT "$XARGS_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
n=${#JOB_KIND[@]}
i=0
while [[ $i -lt $n ]]; do
  case "${JOB_KIND[$i]}" in
    bash|py|pyin) printf '%s\0' "${JOB_KIND[$i]}" "${JOB_DIR[$i]}" "${JOB_FILE[$i]}" "$WORK/$i" ;;
  esac
  i=$((i + 1))
done >"$WORK/jobs.list"
# A worker that dies hard makes xargs abort; the missing result files then count as failures below.
xargs -0 -n 4 -P "$JOBS" bash "$0" --worker <"$WORK/jobs.list" &
XARGS_PID=$!
wait "$XARGS_PID" 2>/dev/null || true
XARGS_PID=""

i=0
while [[ $i -lt $n ]]; do
  case "${JOB_KIND[$i]}" in
    text) echo "${JOB_FILE[$i]}" ;;
    skip)
      echo "  SKIP  ${JOB_FILE[$i]}  (integration — use RUN_INTEGRATION=1 to run)"
      skip=$((skip + 1))
      ;;
    *)
      rc=1
      [[ -f "$WORK/$i.rc" ]] && rc=$(cat "$WORK/$i.rc")
      if [[ "$rc" == "0" ]]; then
        echo "  PASS  ${JOB_FILE[$i]}"
        pass=$((pass + 1))
      else
        echo "  FAIL  ${JOB_FILE[$i]}"
        if [[ -f "$WORK/$i.out" ]]; then
          printf '%s\n' "$(cat "$WORK/$i.out")" | sed 's/^/        /'
        else
          echo "        runner produced no output (job did not run)"
        fi
        fail=$((fail + 1))
      fi
      ;;
  esac
  i=$((i + 1))
done

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
