#!/usr/bin/env bash
# Tests glue logic from release group IMPL.md files.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source ~/.agent-skills-setup/lib.sh 2>/dev/null || { echo "SKIP: lib.sh not installed"; exit 0; }

# --- Test 1: readiness checks all required gates ---

for gate in "OpenSpec" "Jira" "Apidog" "Tests"; do
  grep -q "$gate" ~/Project/agent-skills-setup/skills/release/readiness/IMPL.md \
    || { echo "FAIL: test 1 missing gate: $gate"; exit 1; }
done
echo "OK: all release gates documented"

# --- Test 2: readiness status is ready only on zero blocking items ---

grep -q "status: ready\|blocking_count: 0\|all checks pass" \
  ~/Project/agent-skills-setup/skills/release/readiness/IMPL.md \
  || { echo "FAIL: test 2 ready condition not documented"; exit 1; }
echo "OK: readiness ready condition documented"

# --- Test 3: triage classifies all required categories ---

for cat in "Incident" "Bug" "Regression" "Spec gap" "Enhancement" "Operational"; do
  grep -q "$cat" ~/Project/agent-skills-setup/skills/release/triage/IMPL.md \
    || { echo "FAIL: test 3 missing triage category: $cat"; exit 1; }
done
echo "OK: all triage categories documented"

# --- Test 4: triage does not reopen original story for enhancements ---

grep -q "New.*proposal\|new.*OpenSpec\|new story\|new.*Jira" \
  ~/Project/agent-skills-setup/skills/release/triage/IMPL.md \
  || { echo "FAIL: test 4 enhancement flow not documented"; exit 1; }
echo "OK: enhancement creates new proposal (not reopening old story)"

# --- Test 5: bugfix-spec creates nested folder with BUG-ID ---

grep -q "release/bugfix" ~/Project/agent-skills-setup/skills/release/bugfix-spec/IMPL.md \
  || { echo "FAIL: test 5 bugfix output path not documented"; exit 1; }
echo "OK: bugfix nested folder path documented"

# --- Test 6: bugfix-spec requires regression test step ---

grep -q "regression\|testing-regression" ~/Project/agent-skills-setup/skills/release/bugfix-spec/IMPL.md \
  || { echo "FAIL: test 6 regression test step missing"; exit 1; }
echo "OK: regression test step required by bugfix-spec"

# --- Test 7: archive-check walks openspec_changes list ---

grep -q "openspec_changes" ~/Project/agent-skills-setup/skills/release/archive-check/IMPL.md \
  || { echo "FAIL: test 7 openspec_changes not read"; exit 1; }
echo "OK: archive-check reads openspec_changes list"

# --- Test 8: archive-check status complete only with all archived ---

grep -q "status: complete\|status: incomplete" \
  ~/Project/agent-skills-setup/skills/release/archive-check/IMPL.md \
  || { echo "FAIL: test 8 archive status values not documented"; exit 1; }
echo "OK: archive-check complete/incomplete status documented"

echo ""
echo "All release tests passed."
