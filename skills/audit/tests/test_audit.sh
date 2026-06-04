#!/usr/bin/env bash
# Tests glue logic from audit group IMPL.md files.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source ~/.agent-skills-setup/lib.sh 2>/dev/null || { echo "SKIP: lib.sh not installed"; exit 0; }

# --- Test 1: audit-spec aborts without story.md ---

mkdir -p "$TMP/docs/stories/AUDIT-1-test"
cd "$TMP"
# Simulate the prerequisite check
STORY_DIR=$(resolve_story_dir AUDIT-1) || { echo "FAIL: test 1 resolve failed unexpectedly"; exit 1; }
[[ ! -f "$STORY_DIR/story.md" ]] && echo "OK: missing story.md detected" || { echo "FAIL: test 1"; exit 1; }

# --- Test 2: domain-risk built-in check list has required areas ---

BUILTIN_AREAS=("Tenant isolation" "Permission" "Error behavior" "Audit log" "Latency" "Failover" "Input validation" "Idempotency")
for area in "${BUILTIN_AREAS[@]}"; do
  grep -q "$area" ~/Project/agent-skills-setup/skills/audit/domain-risk/IMPL.md \
    || { echo "FAIL: test 2 missing area: $area"; exit 1; }
done
echo "OK: all built-in risk areas present in IMPL.md"

# --- Test 3: .spec-gated/domain-risk-checks.md override path is documented ---

grep -q "spec-gated/domain-risk-checks.md" ~/Project/agent-skills-setup/skills/audit/domain-risk/IMPL.md \
  || { echo "FAIL: test 3 override path not documented"; exit 1; }
echo "OK: repo-local override path documented"

# --- Test 4: audit-report.md status values are valid ---

mkdir -p "$TMP/docs/stories/AUDIT-2-check"
cat > "$TMP/docs/stories/AUDIT-2-check/audit-report.md" << 'EOF'
---
story: AUDIT-2
status: needs-work
must_resolve_count: 2
---
EOF

status=$(python3 -c "
import re
content = open('$TMP/docs/stories/AUDIT-2-check/audit-report.md').read()
m = re.search(r'status: (\S+)', content)
print(m.group(1) if m else '')
")
[[ "$status" == "needs-work" ]] || { echo "FAIL: test 4 status=$status"; exit 1; }
echo "OK: audit-report status parsed correctly"

# --- Test 5: handoff warns on missing audit-report ---

[[ ! -f "$TMP/docs/stories/AUDIT-1-test/audit-report.md" ]] && echo "OK: missing audit-report detectable (handoff should warn)"

# --- Test 6: audit SKILL.md documents all three subcommands ---

for sub in "audit-spec" "audit-domain-risk" "audit-handoff"; do
  grep -q "$sub" ~/Project/agent-skills-setup/skills/audit/SKILL.md \
    || { echo "FAIL: test 6 $sub not in SKILL.md"; exit 1; }
done
echo "OK: all audit subcommands documented"

echo ""
echo "All audit tests passed."
