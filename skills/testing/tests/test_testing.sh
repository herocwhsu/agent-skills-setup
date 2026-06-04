#!/usr/bin/env bash
# Tests glue logic from testing group IMPL.md files.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source ~/.agent-skills-setup/lib.sh 2>/dev/null || { echo "SKIP: lib.sh not installed"; exit 0; }

# --- Test 1: test-plan.md output path is under story dir ---

grep -q 'STORY_DIR.*test-plan.md\|test-plan.md' \
  ~/Project/agent-skills-setup/skills/testing/plan/IMPL.md \
  || { echo "FAIL: test 1 test-plan.md path not documented"; exit 1; }
echo "OK: test-plan.md output path documented"

# --- Test 2: test plan covers all test layers ---

for layer in "Unit" "Integration" "API" "Regression" "Manual"; do
  grep -q "$layer" ~/Project/agent-skills-setup/skills/testing/plan/IMPL.md \
    || { echo "FAIL: test 2 missing layer: $layer"; exit 1; }
done
echo "OK: all test layers documented"

# --- Test 3: qa-check reports PASS only on full coverage ---

grep -q "Status: PASS\|Status: FAIL" \
  ~/Project/agent-skills-setup/skills/testing/qa-check/IMPL.md \
  || { echo "FAIL: test 3 PASS/FAIL verdict not documented"; exit 1; }
echo "OK: qa-check PASS/FAIL verdict documented"

# --- Test 4: qa-check covers permission test category ---

grep -q "permission\|Permission" \
  ~/Project/agent-skills-setup/skills/testing/qa-check/IMPL.md \
  || { echo "FAIL: test 4 permission coverage not checked"; exit 1; }
echo "OK: permission coverage in qa-check"

# --- Test 5: regression IMPL.md requires a trigger artifact ---

grep -q "change-requests\|bugfix" \
  ~/Project/agent-skills-setup/skills/testing/regression/IMPL.md \
  || { echo "FAIL: test 5 trigger artifact not documented"; exit 1; }
echo "OK: regression trigger artifact documented"

# --- Test 6: testing SKILL.md enforces test-before-implementation gate ---

grep -q "before implementation\|before.*implementation\|planned before" \
  ~/Project/agent-skills-setup/skills/testing/SKILL.md \
  || { echo "FAIL: test 6 test-first gate not in SKILL.md"; exit 1; }
echo "OK: test-first gate in SKILL.md"

# --- Test 7: no-regression-test-no-closure rule is documented ---

grep -q "No regression test\|regression test.*closure\|no bugfix closure" \
  ~/Project/agent-skills-setup/skills/testing/SKILL.md \
  || grep -q "No regression test" \
    ~/Project/agent-skills-setup/skills/testing/regression/IMPL.md \
  || { echo "FAIL: test 7 no-regression rule not documented"; exit 1; }
echo "OK: no-regression-test-no-closure rule documented"

echo ""
echo "All testing tests passed."
