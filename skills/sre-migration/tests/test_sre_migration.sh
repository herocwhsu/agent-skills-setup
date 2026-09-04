#!/usr/bin/env bash
# Tests the sre-migration skill's structure, reachability, and public-repo hygiene.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILL_DIR="$REPO_DIR/skills/sre-migration"
SUBS="scaffold draft lint ticket"

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Test 1: SKILL.md carries the two-key frontmatter every group uses ---

if [[ -f "$SKILL_DIR/SKILL.md" ]] &&
  grep -q '^name: sre-migration$' "$SKILL_DIR/SKILL.md" &&
  grep -q '^description: .' "$SKILL_DIR/SKILL.md"; then
  ok "SKILL.md has name + description frontmatter"
else
  bad "SKILL.md missing or lacks name/description frontmatter"
fi

# --- Test 2: recipes are reachable from SKILL.md (commit 90b3429) ---
# That audit found 7 groups whose SKILL.md gave an agent no textual path to the
# recipe. Both halves matter: the file must exist AND the table must name it.

unreachable=""
for sub in $SUBS; do
  [[ -f "$SKILL_DIR/$sub/IMPL.md" ]] || unreachable="$unreachable no-file:$sub"
  grep -qF "$sub/IMPL.md" "$SKILL_DIR/SKILL.md" 2>/dev/null ||
    unreachable="$unreachable not-in-table:$sub"
done
if [[ -z "$unreachable" ]]; then
  ok "all four recipes exist and are named in the subcommand table"
else
  bad "unreachable recipes:$unreachable"
fi

# --- Test 3: every subcommand declares its slash command ---

missing_slash=""
for sub in $SUBS; do
  grep -qF "/sre-migration-$sub" "$SKILL_DIR/SKILL.md" 2>/dev/null ||
    missing_slash="$missing_slash $sub"
done
if [[ -z "$missing_slash" ]]; then
  ok "all four slash commands declared in SKILL.md"
else
  bad "slash command not declared for:$missing_slash"
fi

# --- Test 4: no real host or numeric Jira id is hardcoded ---
# This repo is public. Hosts belong in config.sh; Jira ids resolve by name at
# runtime, which also survives a site being re-pointed.

leaked=""
if [[ -d "$SKILL_DIR" ]]; then
  while IFS= read -r f; do
    if grep -qE 'atlassian\.net|customfield_[0-9]+' "$f"; then
      leaked="$leaked ${f#"$SKILL_DIR"/}"
    fi
  done < <(find "$SKILL_DIR" -type f -name '*.md' -o -type f -name '*.sh' -o -type f -name '*.json')
fi
if [[ -z "$leaked" ]]; then
  ok "no hardcoded hosts or numeric custom-field ids"
else
  bad "hardcoded host/id in:$leaked"
fi

echo ""
echo "sre-migration: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
