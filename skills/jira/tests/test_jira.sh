#!/usr/bin/env bash
# Tests glue logic from jira/evidence IMPL.md.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: no-evidence-no-closure rule is documented ---

grep -q "No evidence\|no closure\|No.*closure" \
  ~/Project/agent-skills-setup/skills/jira/evidence/IMPL.md \
  || { echo "FAIL: test 1 no-evidence rule not documented"; exit 1; }
echo "OK: no-evidence-no-closure rule documented"

# --- Test 2: evidence types cover all workflow spec §13 requirements ---

for evidence in "PR link" "Apidog" "CI link" "OpenSpec"; do
  grep -q "$evidence" ~/Project/agent-skills-setup/skills/jira/evidence/IMPL.md \
    || { echo "FAIL: test 2 missing evidence type: $evidence"; exit 1; }
done
echo "OK: all evidence types covered"

# --- Test 3: READY verdict requires all evidence present ---

grep -q "Status: READY\|Status: NOT READY" \
  ~/Project/agent-skills-setup/skills/jira/evidence/IMPL.md \
  || { echo "FAIL: test 3 verdict not documented"; exit 1; }
echo "OK: READY/NOT READY verdict documented"

# --- Test 4: merged PR check (not draft) is documented ---

grep -q "merged\|draft" ~/Project/agent-skills-setup/skills/jira/evidence/IMPL.md \
  || { echo "FAIL: test 4 merged-PR requirement not documented"; exit 1; }
echo "OK: merged PR requirement documented"

echo ""
echo "All jira tests passed."
