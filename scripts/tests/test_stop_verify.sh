#!/usr/bin/env bash
# test_stop_verify.sh — harness/guards/stop-verify.sh runs harness-verify on stop,
# except during an outside-agent review, which the agy allowlist keeps read-only.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$(cd "$SCRIPT_DIR/../harness/guards" && pwd)/stop-verify.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

R="$TMP/repo"; mkdir -p "$R/scripts"
git -C "$R" init -q
printf '#!/usr/bin/env bash\ntouch "%s/ran"\necho "runtime drift" >&2\nexit 1\n' "$R" > "$R/scripts/harness-verify.sh"
AGY_IN='{"terminationReason":"done","conversationId":"c"}'

out=$(cd "$R" && printf '%s' "$AGY_IN" | OUTSIDE_AGENT_PURPOSE=review bash "$HOOK"); rc=$?
if [[ $rc -eq 0 && "$out" == "{}" && ! -e "$R/ran" ]]; then ok "an outside-agent review stops without running the gates"; else bad "review stop" "rc=$rc out=$out"; fi

out=$(cd "$R" && printf '%s' "$AGY_IN" | env -u OUTSIDE_AGENT_PURPOSE bash "$HOOK"); rc=$?
if [[ $rc -eq 0 && "$out" == *'"continue"'* && "$out" == *"runtime drift"* && -e "$R/ran" ]]; then ok "any other agy stop runs the gates and continues on failure"; else bad "plain agy stop" "rc=$rc out=$out"; fi

rm -f "$R/ran"
out=$(cd "$R" && printf '{}' | env -u OUTSIDE_AGENT_PURPOSE bash "$HOOK" 2>&1); rc=$?
if [[ $rc -eq 2 && -e "$R/ran" ]]; then ok "a claude stop still blocks with exit 2"; else bad "claude stop" "rc=$rc out=$out"; fi

echo ""
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
