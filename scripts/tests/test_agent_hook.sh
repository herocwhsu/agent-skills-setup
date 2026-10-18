#!/usr/bin/env bash
# test_agent_hook.sh — common/agent-hook.sh runs an unchanged (Claude-shaped)
# shared hook for agy and codex: input in, the agent's own answer out.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WRAP="$(cd "$SCRIPT_DIR/../templates/hooks/common" && pwd)/agent-hook.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# A hook that logs the file it was given and fails for any path containing "bad".
cat > "$TMP/hook.sh" <<'HOOK'
#!/usr/bin/env bash
f=$(python3 -c 'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("file_path",""))')
echo "$f" >> "$LOG"
case "$f" in *bad*) echo "hook says no: $f" >&2; exit 2 ;; esac
exit 0
HOOK
cat > "$TMP/stop-fail.sh" <<'HOOK'
#!/usr/bin/env bash
echo "gate failed: details" >&2; exit 2
HOOK
cat > "$TMP/stop-ok.sh" <<'HOOK'
#!/usr/bin/env bash
exit 0
HOOK
export LOG="$TMP/log"

run() { # <stdin> <args...> -> sets RC OUT ERR
  local in="$1"; shift
  : > "$LOG"
  OUT=$(printf '%s' "$in" | bash "$WRAP" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}

run '{"toolCall":{"name":"write_to_file","args":{"TargetFile":"/r/good.sh"}},"conversationId":"c"}' agy edit "$TMP/hook.sh"
if [[ $RC -eq 0 && "$OUT" == "{}" && "$(cat "$LOG")" == "/r/good.sh" ]]; then ok "agy edit passes TargetFile and prints {} on success"; else bad "agy edit success" "rc=$RC out=$OUT log=$(cat "$LOG")"; fi

run '{"toolCall":{"name":"replace_file_content","args":{"AbsolutePath":"/r/bad.sh"}},"conversationId":"c"}' agy edit "$TMP/hook.sh"
if [[ $RC -eq 2 && "$ERR" == *"hook says no: /r/bad.sh"* ]]; then ok "agy edit blocks with exit 2 and the hook's stderr"; else bad "agy edit failure" "rc=$RC err=$ERR"; fi

run '{"terminationReason":"done","conversationId":"c"}' agy stop "$TMP/stop-fail.sh"
dec=$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("decision"), "details" in d.get("reason",""))' 2>/dev/null)
if [[ $RC -eq 0 && "$dec" == "continue True" ]]; then ok "agy stop answers decision continue with the reason"; else bad "agy stop failure" "rc=$RC out=$OUT"; fi

run '{"terminationReason":"done","conversationId":"c"}' agy stop "$TMP/stop-ok.sh"
if [[ $RC -eq 0 && "$OUT" == "{}" ]]; then ok "agy stop prints {} on success"; else bad "agy stop success" "rc=$RC out=$OUT"; fi

patch='*** Begin Patch\n*** Update File: /r/one.sh\n@@\n-a\n+b\n*** Add File: /r/two.sh\n+x\n*** End Patch'
run "{\"tool_name\":\"apply_patch\",\"tool_input\":{\"command\":[\"apply_patch\",\"$patch\"]}}" codex edit "$TMP/hook.sh"
if [[ $RC -eq 0 && "$(tr '\n' ' ' < "$LOG")" == "/r/one.sh /r/two.sh " ]]; then ok "codex edit runs the hook once per patched file"; else bad "codex edit files" "rc=$RC log=$(cat "$LOG")"; fi

patch2='*** Begin Patch\n*** Update File: /r/one.sh\n*** Update File: /r/bad.sh\n*** End Patch'
run "{\"tool_name\":\"apply_patch\",\"tool_input\":{\"input\":\"$patch2\"}}" codex edit "$TMP/hook.sh"
if [[ $RC -eq 2 && "$ERR" == *"bad.sh"* ]]; then ok "codex edit blocks when any patched file fails"; else bad "codex edit failure" "rc=$RC err=$ERR"; fi

# apply_patch names files relative to the session's folder (its "cwd"), which can
# be a subfolder: the repo wiring runs this from the repo root.
patch3='*** Begin Patch\n*** Update File: lib/one.sh\n*** End Patch'
run "{\"cwd\":\"/r/sub\",\"tool_name\":\"apply_patch\",\"tool_input\":{\"input\":\"$patch3\"}}" codex edit "$TMP/hook.sh"
if [[ $RC -eq 0 && "$(cat "$LOG")" == "/r/sub/lib/one.sh" ]]; then ok "codex edit makes a relative patch path absolute against the input's cwd"; else bad "codex relative path" "rc=$RC log=$(cat "$LOG")"; fi

run '{"tool_name":"Edit","tool_input":{"file_path":"/r/direct.sh"}}' codex edit "$TMP/hook.sh"
if [[ $RC -eq 0 && "$(cat "$LOG")" == "/r/direct.sh" ]]; then ok "codex edit passes a plain file_path through"; else bad "codex edit file_path" "rc=$RC log=$(cat "$LOG")"; fi

run '{}' codex stop "$TMP/stop-fail.sh"
if [[ $RC -eq 2 && "$ERR" == *"gate failed"* ]]; then ok "codex stop passes the exit code and stderr through"; else bad "codex stop" "rc=$RC err=$ERR"; fi

cat > "$TMP/crash.sh" <<'HOOK'
#!/usr/bin/env bash
echo "internal error" >&2; exit 1
HOOK
run '{"toolCall":{"args":{"TargetFile":"/r/x.sh"}},"conversationId":"c"}' agy edit "$TMP/crash.sh"
if [[ $RC -eq 0 && "$OUT" == "{}" ]]; then ok "a hook error other than exit 2 does not block, as in Claude"; else bad "non-2 exit" "rc=$RC out=$OUT"; fi

run '{}' claude edit "$TMP/hook.sh"
if [[ $RC -ne 0 ]]; then ok "an unknown agent is refused"; else bad "unknown agent" "rc=$RC"; fi

echo ""
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
