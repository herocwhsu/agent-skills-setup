#!/usr/bin/env bash
# Tests glue logic from intake/spec-summary IMPL.md.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source ~/.agent-skills-setup/lib.sh 2>/dev/null || { echo "SKIP: lib.sh not installed"; exit 0; }

# --- Test 1: story_slug_from_summary produces clean slug ---

slug=$(story_slug_from_summary "Add Camera Group Filter to Events API")
[[ "$slug" == "add-camera-group-filter-to-events-api" ]] || { echo "FAIL: test 1 got $slug"; exit 1; }
echo "OK: slug derived correctly"

# --- Test 2: story_slug_from_summary strips punctuation ---

slug=$(story_slug_from_summary "Fix: Permission Leak (urgent!)")
[[ "$slug" == "fix-permission-leak-urgent" ]] || { echo "FAIL: test 2 got $slug"; exit 1; }
echo "OK: punctuation stripped"

# --- Test 3: story_slug_from_summary caps at 50 chars ---

slug=$(story_slug_from_summary "This Is A Very Long Story Title That Goes Well Beyond The Fifty Character Maximum Limit")
[[ ${#slug} -le 50 ]] || { echo "FAIL: test 3 slug length ${#slug} > 50"; exit 1; }
echo "OK: slug capped at 50 chars"

# --- Test 4: resolve_story_dir finds one match ---

mkdir -p "$TMP/docs/stories/PROJ-100-my-feature"
cd "$TMP"
result=$(resolve_story_dir PROJ-100)
[[ "$result" == "./docs/stories/PROJ-100-my-feature" ]] || { echo "FAIL: test 4 got $result"; exit 1; }
echo "OK: resolve_story_dir single match"

# --- Test 5: resolve_story_dir fails on zero matches ---

cd "$TMP"
if resolve_story_dir MISSING-999 2>/dev/null; then
  echo "FAIL: test 5 expected non-zero exit"
  exit 1
fi
echo "OK: missing story rejected"

# --- Test 6: resolve_story_dir fails on multiple matches ---

mkdir -p "$TMP/docs/stories/PROJ-200-foo" "$TMP/docs/stories/PROJ-200-bar"
cd "$TMP"
if resolve_story_dir PROJ-200 2>/dev/null; then
  echo "FAIL: test 6 expected non-zero on ambiguous"
  exit 1
fi
echo "OK: ambiguous story rejected"

# --- Test 7: intake-summary.md frontmatter parses correctly ---

mkdir -p "$TMP/docs/stories/PROJ-300-test"
cat > "$TMP/docs/stories/PROJ-300-test/intake-summary.md" << 'EOF'
---
jira_story: PROJ-300
openspec_changes:
  - proj-300-test-feature
  - proj-300-cr-scope-change
status: implementing
---
EOF

change_ids=$(python3 -c "
import re
content = open('$TMP/docs/stories/PROJ-300-test/intake-summary.md').read()
m = re.search(r'^---\n(.+?)\n---', content, re.DOTALL)
fm = m.group(1)
in_changes = False
ids = []
for line in fm.splitlines():
    if line.strip() == 'openspec_changes:':
        in_changes = True
    elif in_changes and line.strip().startswith('- '):
        ids.append(line.strip()[2:])
    elif in_changes and not line.strip().startswith('-'):
        in_changes = False
print('\n'.join(ids))
")
[[ $(echo "$change_ids" | wc -l) -eq 2 ]] || { echo "FAIL: test 7 expected 2 change_ids"; exit 1; }
echo "OK: frontmatter parsing extracts 2 change-ids"

echo ""
echo "All intake tests passed."
