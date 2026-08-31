#!/usr/bin/env bash
# Tests for .claude/hooks/skill-paths-guard.sh and scripts/skill-path-var-check.py.
#
# Uses SKILL_PATHS_GUARD_REPO_DIR to point at throwaway trees. Asserting only
# against the real skills/ dir would stop being a test the moment the tree is
# clean -- which it is, so every case here builds its own fixture.
#
# Exit 2 is asserted explicitly: it is the only code Claude Code feeds back to
# the agent, and a gate returning 1 presents as a gate while blocking nothing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_DIR/.claude/hooks/skill-paths-guard.sh"
CHECKER="$REPO_DIR/scripts/skill-path-var-check.py"
[[ -f "$HOOK" ]]    || { echo "FAIL: hook not found at $HOOK"; exit 1; }
[[ -f "$CHECKER" ]] || { echo "FAIL: checker not found at $CHECKER"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# fixture <name> <impl-body> -> echoes a repo-shaped dir with skills/grp/sub/IMPL.md
fixture() {
  # Separate statements: `local a=$1 b=$TMP/$a` expands every argument before the
  # builtin assigns any, so $a is still unset there and set -u aborts.
  local name="$1"
  local body="$2"
  local d="$TMP/$name"
  mkdir -p "$d/skills/grp/sub" "$d/scripts"
  cp "$CHECKER" "$d/scripts/skill-path-var-check.py"
  printf '%s\n' "$body" > "$d/skills/grp/sub/IMPL.md"
  echo "$d"
}

run_hook() { SKILL_PATHS_GUARD_REPO_DIR="$1" bash "$HOOK" 2>&1; }

# --- 1. the pre-fix shape blocks with exit 2 -------------------------------
# skills/apidog/diff/IMPL.md shipped exactly this: $REPO_DIR undefined at
# runtime, so the path expanded to /scripts/apidog-share-fetch.py.
d=$(fixture bad '```bash
SCRIPT="$REPO_DIR/scripts/apidog-share-fetch.py"
python3 "$SCRIPT" --help
```')
out=$(run_hook "$d") && code=0 || code=$?
if [[ $code -eq 2 ]]; then ok "undefined repo path blocks with exit 2"
else bad "undefined repo path blocks with exit 2" "exit $code, out: $out"; fi
grep -q 'REPO_DIR' <<<"$out" \
  && ok "message names the offending variable" \
  || bad "message names the offending variable" "out: $out"

# --- 2. defining it first is accepted -------------------------------------
d=$(fixture good '```bash
REPO_DIR=$(setup_repo_dir) || exit 1
SCRIPT="$REPO_DIR/scripts/apidog-share-fetch.py"
```')
out=$(run_hook "$d") && code=0 || code=$?
[[ $code -eq 0 ]] \
  && ok "defined variable passes" \
  || bad "defined variable passes" "exit $code, out: $out"

# --- 3. a definition in a *different* block still counts ------------------
# Recipes are written as several blocks in sequence; requiring each to stand
# alone would flag prose that is correct in context.
d=$(fixture split '```bash
REPO_DIR=$(setup_repo_dir)
```

Then run it:

```bash
python3 "$REPO_DIR/scripts/thing.py"
```')
out=$(run_hook "$d") && code=0 || code=$?
[[ $code -eq 0 ]] \
  && ok "definition in an earlier block counts" \
  || bad "definition in an earlier block counts" "exit $code, out: $out"

# --- 4. config.sh values are not flagged ----------------------------------
# The design constraint. These arrive via load_config and are hostnames/ids, so
# they never form a repo path. A gate flagging them would be all noise and get
# suppressed -- the sh-check.sh failure AGENTS.md records.
d=$(fixture config '```bash
source ~/.agent-skills-setup/lib.sh
load_config
curl -u "$JIRA_USER:$TOKEN" "https://$JIRA_HOST/rest/api/3/issue/$1"
echo "$APIDOG_PROJECT_ID" "$CONFLUENCE_HOST" "$JIRA_PROJECT_KEY"
```')
out=$(run_hook "$d") && code=0 || code=$?
[[ $code -eq 0 ]] \
  && ok "config.sh-provided variables are not flagged" \
  || bad "config.sh-provided variables are not flagged" "exit $code, out: $out"

# --- 5. $HOME paths are not flagged --------------------------------------
# $HOME is always set, and a path under it is the runtime dir, not the repo.
d=$(fixture home '```bash
source "$HOME/.agent-skills-setup/lib.sh"
cat "$HOME/.claude/skills/apidog/SKILL.md"
```')
out=$(run_hook "$d") && code=0 || code=$?
[[ $code -eq 0 ]] \
  && ok "\$HOME paths are not flagged" \
  || bad "\$HOME paths are not flagged" "exit $code, out: $out"

# --- 6. a placeholder that is not a path is not flagged ------------------
# SHARE_URL/STORY_ID and friends are deliberate fill-ins the operator supplies.
d=$(fixture placeholder '```bash
SHARE_UUID=$(echo "$SHARE_URL" | grep -oE "[0-9a-f-]{36}")
echo "story: $STORY_ID subtask: $SUBTASK_ID"
```')
out=$(run_hook "$d") && code=0 || code=$?
[[ $code -eq 0 ]] \
  && ok "non-path placeholders are not flagged" \
  || bad "non-path placeholders are not flagged" "exit $code, out: $out"

# --- 7. the checker itself exits 1, not 2 -------------------------------
# It is a CLI; only the hook translates failure into a block.
d=$(fixture cli '```bash
python3 "$NOPE/scripts/x.py"
```')
python3 "$CHECKER" "$d/skills" >/dev/null 2>&1 && code=0 || code=$?
[[ $code -eq 1 ]] \
  && ok "checker exits 1 (CLI), hook exits 2 (block)" \
  || bad "checker exits 1 (CLI), hook exits 2 (block)" "exit $code"

# --- 8. the real tree passes -------------------------------------------
out=$(bash "$HOOK" 2>&1) && code=0 || code=$?
[[ $code -eq 0 ]] \
  && ok "the repo's own skills/ tree is clean" \
  || bad "the repo's own skills/ tree is clean" "exit $code, out: $out"

echo ""
echo "test_skill_paths_guard: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
