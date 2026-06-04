#!/usr/bin/env bash
# Tests glue logic from external/deps IMPL.md.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source ~/.agent-skills-setup/lib.sh 2>/dev/null || { echo "SKIP: lib.sh not installed"; exit 0; }

# --- Test 1: external-deps.md output path is under story dir ---

grep -q 'STORY_DIR.*external-deps.md\|external-deps.md' \
  ~/Project/agent-skills-setup/skills/external/deps/IMPL.md \
  || { echo "FAIL: test 1 output path not documented"; exit 1; }
echo "OK: external-deps.md output path documented"

# --- Test 2: Jira task split rule lists blocked/can-start categories ---

for item in "Can start" "Blocked"; do
  grep -q "$item" ~/Project/agent-skills-setup/skills/external/deps/IMPL.md \
    || { echo "FAIL: test 2 missing task split category: $item"; exit 1; }
done
echo "OK: Jira task split categories present"

# --- Test 3: adapter boundary pattern is documented ---

grep -q "adapter\|Adapter" ~/Project/agent-skills-setup/skills/external/deps/IMPL.md \
  && grep -q "Internal interface" ~/Project/agent-skills-setup/skills/external/deps/IMPL.md \
  || { echo "FAIL: test 3 adapter boundary not documented"; exit 1; }
echo "OK: adapter boundary documented"

# --- Test 4: provisional contract section is present ---

grep -q "Provisional" ~/Project/agent-skills-setup/skills/external/deps/IMPL.md \
  || { echo "FAIL: test 4 provisional contract section missing"; exit 1; }
echo "OK: provisional contract section present"

# --- Test 5: mock provider plan covers error simulation ---

grep -q "Error\|timeout\|rate limit" \
  ~/Project/agent-skills-setup/skills/external/deps/IMPL.md \
  || { echo "FAIL: test 5 error simulation not covered"; exit 1; }
echo "OK: error simulation in mock plan"

# --- Test 6: external-deps frontmatter has blocking_count ---

grep -q "blocking_count" ~/Project/agent-skills-setup/skills/external/deps/IMPL.md \
  || { echo "FAIL: test 6 blocking_count not in frontmatter"; exit 1; }
echo "OK: blocking_count in frontmatter"

echo ""
echo "All external tests passed."
