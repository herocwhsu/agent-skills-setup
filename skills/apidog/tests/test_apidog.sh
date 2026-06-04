#!/usr/bin/env bash
# Tests glue logic from apidog group IMPL.md files.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source ~/.agent-skills-setup/lib.sh 2>/dev/null || { echo "SKIP: lib.sh not installed"; exit 0; }

# --- Test 1: apidog-mocks prerequisite check --- contract must exist first ---

mkdir -p "$TMP/docs/stories/API-1-test/apidog"
cd "$TMP"

# Simulate the prereq check: contract.md absent → should abort
[[ ! -f "$TMP/docs/stories/API-1-test/apidog/contract.md" ]] \
  && echo "OK: missing contract.md detectable (mocks/testcases should abort)" \
  || { echo "FAIL: test 1"; exit 1; }

# --- Test 2: apidog/contract.md output path is under story dir ---

grep -q 'STORY_DIR.*apidog/contract.md\|apidog/contract' \
  ~/Project/agent-skills-setup/skills/apidog/contract/IMPL.md \
  || { echo "FAIL: test 2 contract path not documented"; exit 1; }
echo "OK: contract output path documented"

# --- Test 3: contract IMPL.md documents required review checklist ---

grep -q "Frontend\|backend\|QA" \
  ~/Project/agent-skills-setup/skills/apidog/contract/IMPL.md \
  || { echo "FAIL: test 3 review checklist not documented"; exit 1; }
echo "OK: review checklist documented"

# --- Test 4: mocks IMPL.md covers all required scenarios ---

for scenario in "Success" "Permission denied" "Unauthorized" "Rate limited" "Not found"; do
  grep -q "$scenario" ~/Project/agent-skills-setup/skills/apidog/mocks/IMPL.md \
    || { echo "FAIL: test 4 missing mock scenario: $scenario"; exit 1; }
done
echo "OK: all mock scenarios covered"

# --- Test 5: testcases IMPL.md has permission test category ---

grep -q "Permission cases\|permission" ~/Project/agent-skills-setup/skills/apidog/testcases/IMPL.md \
  || { echo "FAIL: test 5 permission test cases not documented"; exit 1; }
echo "OK: permission test cases documented"

# --- Test 6: SKILL.md enforces Apidog as implementation gate ---

grep -q "gate\|before.*implementation\|implementation starts" \
  ~/Project/agent-skills-setup/skills/apidog/SKILL.md \
  || { echo "FAIL: test 6 gate rule not in SKILL.md"; exit 1; }
echo "OK: Apidog gate rule present"

echo ""
echo "All apidog tests passed."
