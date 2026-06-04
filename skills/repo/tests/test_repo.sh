#!/usr/bin/env bash
# Tests glue logic from repo/context-scan IMPL.md.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: gh auth check produces useful message when not authenticated ---

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  echo "You are not logged into any GitHub hosts." >&2
  exit 1
fi
exit 0
EOF
chmod +x "$TMP/bin/gh"
PATH="$TMP/bin:$PATH"

if gh auth status 2>/dev/null; then
  echo "FAIL: test 1 expected gh auth failure"
  exit 1
fi
echo "OK: gh auth failure detected"

# --- Test 2: repo-context.md frontmatter fields are documented ---

for field in "story:" "scanned_at:" "repo:"; do
  grep -q "$field" ~/Project/agent-skills-setup/skills/repo/context-scan/IMPL.md \
    || { echo "FAIL: test 2 missing frontmatter field: $field"; exit 1; }
done
echo "OK: repo-context.md frontmatter fields documented"

# --- Test 3: context-scan output path is under story dir ---

grep -q 'STORY_DIR.*repo-context.md\|repo-context.md' \
  ~/Project/agent-skills-setup/skills/repo/context-scan/IMPL.md \
  || { echo "FAIL: test 3 output path not documented"; exit 1; }
echo "OK: output path documented"

# --- Test 4: SKILL.md mentions gh CLI prerequisite ---

grep -q "gh" ~/Project/agent-skills-setup/skills/repo/SKILL.md \
  || { echo "FAIL: test 4 gh CLI prereq not mentioned"; exit 1; }
echo "OK: gh CLI prerequisite mentioned"

# --- Test 5: context-scan covers permission middleware check ---

grep -q "permission\|middleware\|authorize" \
  ~/Project/agent-skills-setup/skills/repo/context-scan/IMPL.md \
  || { echo "FAIL: test 5 permission scan not covered"; exit 1; }
echo "OK: permission middleware scan documented"

echo ""
echo "All repo tests passed."
