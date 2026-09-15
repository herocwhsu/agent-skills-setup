#!/usr/bin/env bash
# Tests for .claude/hooks/state-layer-guard.sh.
#
# Uses STATE_LAYER_GUARD_REPO_DIR to point at throwaway trees. Asserting only
# against the real feature_list.json/progress.md/init.sh would stop being a
# test the moment those files exist -- which they do, so every failure case
# here builds its own fixture with one of the three missing or malformed.
#
# Exit 2 is asserted explicitly: it is the only code Claude Code feeds back to
# the agent, and a gate returning 1 presents as a gate while blocking nothing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_DIR/.claude/hooks/state-layer-guard.sh"
[[ -f "$HOOK" ]] || { echo "FAIL: hook not found at $HOOK"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# fixture <name> -> echoes a dir with all three state-layer files present and valid
fixture_complete() {
  local d="$TMP/$1"
  mkdir -p "$d"
  echo '{"features": []}' > "$d/feature_list.json"
  echo '# progress' > "$d/progress.md"
  echo '#!/usr/bin/env bash' > "$d/init.sh"
  echo "$d"
}

run_hook() { STATE_LAYER_GUARD_REPO_DIR="$1" bash "$HOOK" 2>&1; }

# --- 1. all three files present and valid JSON: passes ---------------------
d=$(fixture_complete complete)
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 0 ]] \
  && ok "complete state layer passes" \
  || bad "complete state layer passes" "exit $status, out: $out"

# --- 2. feature_list.json missing: blocks with exit 2 ----------------------
d=$(fixture_complete missing-feature-list)
rm "$d/feature_list.json"
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 2 ]] \
  && ok "missing feature_list.json blocks with exit 2" \
  || bad "missing feature_list.json blocks with exit 2" "exit $status, out: $out"
grep -q 'feature_list.json' <<<"$out" \
  && ok "message names the missing file" \
  || bad "message names the missing file" "out: $out"

# --- 3. progress.md missing: blocks with exit 2 -----------------------------
d=$(fixture_complete missing-progress)
rm "$d/progress.md"
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 2 ]] \
  && ok "missing progress.md blocks with exit 2" \
  || bad "missing progress.md blocks with exit 2" "exit $status, out: $out"

# --- 4. init.sh missing: blocks with exit 2 --------------------------------
d=$(fixture_complete missing-init)
rm "$d/init.sh"
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 2 ]] \
  && ok "missing init.sh blocks with exit 2" \
  || bad "missing init.sh blocks with exit 2" "exit $status, out: $out"

# --- 5. all three missing: reports all three, not just the first -----------
d="$TMP/all-missing"
mkdir -p "$d"
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 2 ]] \
  && ok "all three missing blocks with exit 2" \
  || bad "all three missing blocks with exit 2" "exit $status, out: $out"
for f in feature_list.json progress.md init.sh; do
  grep -q "$f" <<<"$out" \
    && ok "message names $f among the missing" \
    || bad "message names $f among the missing" "out: $out"
done

# --- 6. feature_list.json present but not valid JSON: blocks with exit 2 ---
d=$(fixture_complete bad-json)
echo 'not json' > "$d/feature_list.json"
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 2 ]] \
  && ok "malformed feature_list.json blocks with exit 2" \
  || bad "malformed feature_list.json blocks with exit 2" "exit $status, out: $out"
grep -qi 'json' <<<"$out" \
  && ok "message names the JSON problem" \
  || bad "message names the JSON problem" "out: $out"

# --- 7. the real repo's own state layer passes ------------------------------
set +e; out=$(bash "$HOOK" 2>&1); status=$?; set -e
[[ $status -eq 0 ]] \
  && ok "this repo's own state layer is clean" \
  || bad "this repo's own state layer is clean" "exit $status, out: $out"

echo ""
echo "test_state_layer_guard: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
