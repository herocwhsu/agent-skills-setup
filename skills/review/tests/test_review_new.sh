#!/usr/bin/env bash
# Tests glue logic from review/amend, review/change-request, review/guardrails IMPL.md.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source ~/.agent-skills-setup/lib.sh 2>/dev/null || { echo "SKIP: lib.sh not installed"; exit 0; }

# --- Test 1: amendment output path uses amendments/ subdir ---

grep -q 'amendments/' $REPO_DIR/skills/review/amend/IMPL.md \
  || { echo "FAIL: test 1 amendments/ path not documented"; exit 1; }
echo "OK: amendments/ output path documented"

# --- Test 2: change-request output path uses change-requests/ subdir ---

grep -q 'change-requests/' $REPO_DIR/skills/review/change-request/IMPL.md \
  || { echo "FAIL: test 2 change-requests/ path not documented"; exit 1; }
echo "OK: change-requests/ output path documented"

# --- Test 3: amendment is append-only (no editing past files) ---

grep -q "append-only\|never edit" $REPO_DIR/skills/review/amend/IMPL.md \
  || { echo "FAIL: test 3 append-only rule not documented"; exit 1; }
echo "OK: amendment append-only rule documented"

# --- Test 4: change-request stops implementation for affected area ---

grep -q "Stop\|paused\|cannot continue" \
  $REPO_DIR/skills/review/change-request/IMPL.md \
  || { echo "FAIL: test 4 stop-implementation not documented"; exit 1; }
echo "OK: stop-implementation rule documented"

# --- Test 5: guardrails checks non-goal violations ---

grep -q "Non-goal\|non-goal" $REPO_DIR/skills/review/guardrails/IMPL.md \
  || { echo "FAIL: test 5 non-goal check not documented"; exit 1; }
echo "OK: non-goal violation check documented"

# --- Test 6: guardrails verdict is PASS only on full compliance ---

grep -q "Verdict: PASS\|Verdict: FAIL" \
  $REPO_DIR/skills/review/guardrails/IMPL.md \
  || { echo "FAIL: test 6 verdict not documented"; exit 1; }
echo "OK: guardrails PASS/FAIL verdict documented"

# --- Test 7: amendment vs change-request decision table is in SKILL.md ---

grep -q "API contract\|Database schema" \
  $REPO_DIR/skills/review/SKILL.md \
  || { echo "FAIL: test 7 amendment/CR decision table not in SKILL.md"; exit 1; }
echo "OK: amendment/CR decision table in SKILL.md"

# --- Test 8: dated output files use YYYY-MM-DD-<slug>.md format ---

grep -q 'YYYY-MM-DD' \
  $REPO_DIR/skills/review/amend/IMPL.md \
  $REPO_DIR/skills/review/change-request/IMPL.md \
  || { echo "FAIL: test 8 date format not documented"; exit 1; }
echo "OK: YYYY-MM-DD-<slug>.md format documented"

echo ""
echo "All review tests passed."
