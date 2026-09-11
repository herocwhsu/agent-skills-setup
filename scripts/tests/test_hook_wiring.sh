#!/usr/bin/env bash
# Tests for hook-wiring-check.py, hook-wiring-guard.sh and _settings_merge.py --rewire.
#
# Every case builds its own throwaway skills tree and its own settings.json. The
# alternative — asserting the real repo currently passes — stops being a test the
# moment the tree is clean, and would not have caught either bug these found:
# a guard that blocked because its checker path was missing rather than because
# the tree was bad, and a rewire loop handed the literal "all" as an agent name.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$REPO_DIR/scripts/hook-wiring-check.py"
MERGE="$REPO_DIR/scripts/_settings_merge.py"
GUARD="$REPO_DIR/.claude/hooks/hook-wiring-guard.sh"
for f in "$CHECK" "$MERGE" "$GUARD"; do
  [[ -f "$f" ]] || { echo "FAIL: missing $f"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)   # macOS mktemp yields /var -> /private/var

fails=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "OK: $label"
  else
    echo "FAIL: $label"
    echo "      expected: $expected"
    echo "      actual:   $actual"
    fails=$((fails + 1))
  fi
}

# make_tree <name> <hook-json> [--no-target]
#   A throwaway skills tree holding one hook.json, target created unless suppressed.
make_tree() {
  local name="$1" json="$2" no_target="${3:-}"
  local d="$TMP/$name"
  mkdir -p "$d/skills/utils/probe/lib"
  printf '%s' "$json" > "$d/skills/utils/probe/hook.json"
  [[ "$no_target" == "--no-target" ]] || touch "$d/skills/utils/probe/lib/p.py"
  echo "$d"
}

PLACEHOLDER='${AGENT_SKILLS_DIR}'
good_json="{\"hooks\":{\"UserPromptSubmit\":[{\"matcher\":\"\",\"hooks\":[{\"type\":\"command\",\"command\":\"python3 ${PLACEHOLDER}/utils/probe/lib/p.py\"}]}]}}"

rc() { local d="$1"; python3 "$CHECK" "$d" >/dev/null 2>&1 && echo 0 || echo 1; }

# --- checker: repo-side validity -------------------------------------------
check "valid hook.json passes" 0 "$(rc "$(make_tree valid "$good_json")")"

bad_event="{\"hooks\":{\"OnUserPrompt\":[{\"hooks\":[{\"command\":\"python3 ${PLACEHOLDER}/utils/probe/lib/p.py\"}]}]}}"
check "unknown event is rejected" 1 "$(rc "$(make_tree badevent "$bad_event")")"

missing="{\"hooks\":{\"UserPromptSubmit\":[{\"hooks\":[{\"command\":\"python3 ${PLACEHOLDER}/utils/probe/lib/gone.py\"}]}]}}"
check "missing command target is rejected" 1 "$(rc "$(make_tree notarget "$missing" --no-target)")"

hardcoded='{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"python3 /Users/someone/.claude/skills/utils/probe/lib/p.py"}]}]}}'
check "hardcoded path is rejected" 1 "$(rc "$(make_tree hardcoded "$hardcoded")")"

no_hooks='{"hooks":{}}'
check "hook.json declaring no hooks is rejected" 1 "$(rc "$(make_tree empty "$no_hooks")")"

# --- checker: machine-side wiring ------------------------------------------
# Absence must never fail: wiring is opt-in through install.sh --with-hook.
tree=$(make_tree wiring "$good_json")
echo '{"model":"x"}' > "$TMP/unwired.json"
python3 "$CHECK" "$tree" "$TMP/unwired.json" >/dev/null 2>&1 \
  && check "an unwired hook is not a failure" 0 0 \
  || check "an unwired hook is not a failure" 0 1

cat > "$TMP/stale.json" <<JSON
{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"python3 /gone/skills/utils/probe/lib/p.py"}]}]}}
JSON
python3 "$CHECK" "$tree" "$TMP/stale.json" >/dev/null 2>&1 \
  && check "a wired-but-unresolvable path is reported" 1 0 \
  || check "a wired-but-unresolvable path is reported" 1 1

# --- guard: blocks with exit 2, and for the right reason -------------------
badtree=$(make_tree guardbad "$bad_event")
set +e
out=$(HOOK_WIRING_GUARD_REPO_DIR="$badtree" bash "$GUARD" 2>&1); guard_rc=$?
set -e
check "guard blocks a bad tree with exit 2" 2 "$guard_rc"
# The reason matters: an earlier draft derived the checker path from the same
# overridable variable, so it "blocked" on a missing checker rather than on the
# tree. That passes an exit-code assertion while testing nothing.
if [[ "$out" == *"unknown event"* ]]; then
  echo "OK: guard blocked on the tree defect, not a missing checker"
else
  echo "FAIL: guard blocked for the wrong reason"
  printf '%s\n' "$out" | sed 's/^/      /'
  fails=$((fails + 1))
fi

set +e
bash "$GUARD" >/dev/null 2>&1; real_rc=$?
set -e
check "guard passes on the real repo tree" 0 "$real_rc"

# --- rewire: refresh in place, never add ----------------------------------
SK="$TMP/newskills"
mkdir -p "$SK/utils/probe/lib"
touch "$SK/utils/probe/lib/p.py"
printf '%s' "$good_json" > "$TMP/hook.json"
sed "s|${PLACEHOLDER}|$SK|g" "$TMP/hook.json" > "$TMP/hook_resolved.json"

cat > "$TMP/a.json" <<JSON
{"model":"x","hooks":{"UserPromptSubmit":[{"matcher":"","hooks":[{"type":"command","command":"python3 /old/gone/skills/utils/probe/lib/p.py"}]}]}}
JSON
python3 "$MERGE" --rewire "$TMP/hook_resolved.json" "$TMP/a.json" --skills-dir "$SK" >/dev/null
check "stale wired path is refreshed" "yes" \
  "$(python3 -c "
import json
d=json.load(open('$TMP/a.json'))
c=d['hooks']['UserPromptSubmit'][0]['hooks'][0]['command']
print('yes' if '$SK' in c else 'no')")"
check "unrelated settings keys survive rewire" "yes" \
  "$(python3 -c "
import json
print('yes' if 'model' in json.load(open('$TMP/a.json')) else 'no')")"
check "matcher survives rewire" "yes" \
  "$(python3 -c "
import json
d=json.load(open('$TMP/a.json'))
print('yes' if 'matcher' in d['hooks']['UserPromptSubmit'][0] else 'no')")"

echo '{"model":"x"}' > "$TMP/b.json"
python3 "$MERGE" --rewire "$TMP/hook_resolved.json" "$TMP/b.json" --skills-dir "$SK" >/dev/null
check "rewire never adds an unwired hook" "no" \
  "$(python3 -c "
import json
print('yes' if 'hooks' in json.load(open('$TMP/b.json')) else 'no')")"

cp "$TMP/a.json" "$TMP/c.json"
before=$(python3 -c "import hashlib;print(hashlib.md5(open('$TMP/c.json','rb').read()).hexdigest())")
python3 "$MERGE" --rewire "$TMP/hook_resolved.json" "$TMP/c.json" --skills-dir "$SK" >/dev/null
after=$(python3 -c "import hashlib;print(hashlib.md5(open('$TMP/c.json','rb').read()).hexdigest())")
check "rewire is idempotent" "$before" "$after"

set +e
python3 "$MERGE" --rewire "$TMP/hook_resolved.json" "$TMP/a.json" >/dev/null 2>&1; nodir_rc=$?
set -e
check "--rewire without --skills-dir errors" 2 "$nodir_rc"

cat > "$TMP/e.json" <<JSON
{"hooks":{"UserPromptSubmit":[{"matcher":"","hooks":[{"type":"command","command":"python3 /old/gone/skills/utils/probe/lib/p.py"}]},{"matcher":"","hooks":[{"type":"command","command":"bash /other/tool.sh"}]}]}}
JSON
python3 "$MERGE" --rewire "$TMP/hook_resolved.json" "$TMP/e.json" --skills-dir "$SK" >/dev/null
check "sibling hooks in the same event survive" "2 yes" \
  "$(python3 -c "
import json
a=json.load(open('$TMP/e.json'))['hooks']['UserPromptSubmit']
sib=any('tool.sh' in h.get('command','') for e in a for h in e.get('hooks',[]))
print(len(a), 'yes' if sib else 'no')")"

# --- update.sh must resolve the saved selection, not word-split it ---------
# agent-selection.txt holds "all" or a comma list. Splitting it by hand passes
# "all" to rewire_hooks, whose case statement returns 0 without doing anything.
check "update.sh resolves agents via select_agents" "yes" \
  "$(grep -q 'select_agents "$(cat "$SELECTION_FILE")"' "$REPO_DIR/scripts/update.sh" && echo yes || echo no)"
check "update.sh does not word-split the selection file" "yes" \
  "$(grep -q 'for agent in ${AGENT_ARG' "$REPO_DIR/scripts/update.sh" && echo no || echo yes)"

if [[ $fails -gt 0 ]]; then
  echo ""
  echo "$fails check(s) failed"
  exit 1
fi
echo ""
echo "all checks passed"
