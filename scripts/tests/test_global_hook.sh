#!/usr/bin/env bash
# test_global_hook.sh — global/global-hook.sh runs the global hooks in the repo the
# agent works in (found from the hook input, not the working directory), and
# skips any hook the repo wires itself.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES="$(cd "$SCRIPT_DIR/../templates/hooks" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# The installed layout: the dispatcher next to the hooks it runs.
H="$TMP/hooks"
mkdir -p "$H"
cp "$TEMPLATES/global/global-hook.sh" "$TEMPLATES/common/agent-hook.sh" "$H/"
for name in sh-check secret-scan preflight; do
  cat > "$H/$name.sh" <<HOOK
#!/usr/bin/env bash
in=\$(cat)
f=\$(printf '%s' "\$in" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("file_path",""))' 2>/dev/null)
echo "$name \$PWD \$f" >> "\$LOG"
[[ -e "\$PWD/FAIL" || "\$f" == *bad* ]] && { echo "$name says no" >&2; exit 2; }
echo "$name ran"
exit 0
HOOK
done
export LOG="$TMP/log"

REPO="$TMP/repo"
mkdir -p "$REPO/sub" "$TMP/elsewhere" "$TMP/plain"
git init -q "$REPO"

run() { # <stdin> <args...> -> sets RC OUT ERR; runs from an unrelated folder, like agy
  local in="$1"; shift
  : > "$LOG"
  OUT=$(cd "$TMP/elsewhere" && printf '%s' "$in" | bash "$H/global-hook.sh" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}

run "{\"tool_input\":{\"file_path\":\"$REPO/sub/a.sh\"}}" claude edit
if [[ $RC -eq 0 && "$(cat "$LOG")" == "sh-check $REPO $REPO/sub/a.sh" ]]; then ok "claude edit runs sh-check in the edited file's repo root"; else bad "claude edit" "rc=$RC log=$(cat "$LOG")"; fi

run "{\"tool_input\":{\"file_path\":\"$REPO/sub/bad.sh\"}}" claude edit
if [[ $RC -eq 2 && "$ERR" == *"sh-check says no"* ]]; then ok "claude edit blocks with exit 2 and the hook's stderr"; else bad "claude edit block" "rc=$RC err=$ERR"; fi

run "{\"toolCall\":{\"name\":\"write_to_file\",\"args\":{\"TargetFile\":\"$REPO/sub/a.sh\"}},\"conversationId\":\"c\"}" agy edit
if [[ $RC -eq 0 && "$OUT" == "{}" && "$(cat "$LOG")" == "sh-check $REPO $REPO/sub/a.sh" ]]; then ok "agy edit finds the repo from TargetFile and prints {}"; else bad "agy edit" "rc=$RC out=$OUT log=$(cat "$LOG")"; fi

touch "$REPO/FAIL"
run "{\"conversationId\":\"c\",\"workspacePaths\":[\"$REPO\"]}" agy stop
dec=$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("decision"), "says no" in d.get("reason",""))' 2>/dev/null)
if [[ $RC -eq 0 && "$dec" == "continue True" && "$(cat "$LOG")" == "secret-scan $REPO " ]]; then ok "agy stop runs secret-scan in workspacePaths[0] and answers continue"; else bad "agy stop" "rc=$RC out=$OUT log=$(cat "$LOG")"; fi

run "{\"cwd\":\"$REPO/sub\",\"hook_event_name\":\"Stop\"}" claude stop
if [[ $RC -eq 2 && "$(cat "$LOG")" == "secret-scan $REPO " ]]; then ok "claude stop runs in the repo root of the input's cwd and blocks"; else bad "claude stop" "rc=$RC log=$(cat "$LOG")"; fi
rm -f "$REPO/FAIL"

run "{\"cwd\":\"$REPO\"}" codex stop
if [[ $RC -eq 0 && "$(cat "$LOG")" == "secret-scan $REPO " ]]; then ok "codex stop runs in the input's cwd"; else bad "codex stop" "rc=$RC log=$(cat "$LOG")"; fi

mkdir -p "$REPO/.agents"
echo '{"x":{"PostToolUse":[{"hooks":[{"command":"bash .claude/hooks/sh-check.sh"}]}]}}' > "$REPO/.agents/hooks.json"
run "{\"toolCall\":{\"args\":{\"TargetFile\":\"$REPO/sub/bad.sh\"}},\"conversationId\":\"c\"}" agy edit
if [[ $RC -eq 0 && "$OUT" == "{}" && ! -s "$LOG" ]]; then ok "a hook the repo wires itself is skipped"; else bad "repo override" "rc=$RC out=$OUT log=$(cat "$LOG")"; fi
rm -rf "$REPO/.agents"

# Only the running agent's own repo settings count: a repo that wires sh-check for
# Claude alone still gets the global one under agy.
mkdir -p "$REPO/.claude"
echo '{"hooks":{"PostToolUse":[{"hooks":[{"command":"bash .claude/hooks/sh-check.sh"}]}]}}' > "$REPO/.claude/settings.json"
run "{\"toolCall\":{\"args\":{\"TargetFile\":\"$REPO/sub/a.sh\"}},\"conversationId\":\"c\"}" agy edit
if [[ $RC -eq 0 && "$(cat "$LOG")" == "sh-check $REPO $REPO/sub/a.sh" ]]; then ok "a hook wired for another agent only does not turn the global one off"; else bad "per-agent override" "rc=$RC log=$(cat "$LOG")"; fi
run "{\"tool_input\":{\"file_path\":\"$REPO/sub/a.sh\"}}" claude edit
if [[ $RC -eq 0 && ! -s "$LOG" ]]; then ok "claude skips the global hook its repo settings wire"; else bad "claude override" "rc=$RC log=$(cat "$LOG")"; fi
# the harness repo's own form: an escaped quote right after the name
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"command":"bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/sh-check.sh\""}]}]}}' > "$REPO/.claude/settings.json"
run "{\"tool_input\":{\"file_path\":\"$REPO/sub/a.sh\"}}" claude edit
if [[ $RC -eq 0 && ! -s "$LOG" ]]; then ok "an escaped quote after the name still counts as the repo's hook"; else bad "escaped quote" "rc=$RC log=$(cat "$LOG")"; fi
rm -rf "$REPO/.claude"

# A hook whose name merely contains the global hook's name is a different hook.
mkdir -p "$REPO/.claude"
echo '{"hooks":{"PostToolUse":[{"hooks":[{"command":"bash .claude/hooks/my-sh-check.sh"}]}]}}' > "$REPO/.claude/settings.json"
run "{\"tool_input\":{\"file_path\":\"$REPO/sub/a.sh\"}}" claude edit
if [[ $RC -eq 0 && "$(cat "$LOG")" == "sh-check $REPO $REPO/sub/a.sh" ]]; then ok "a differently named repo hook does not turn the global one off"; else bad "name match" "rc=$RC log=$(cat "$LOG")"; fi
rm -rf "$REPO/.claude"

run "{\"cwd\":\"$REPO\",\"hook_event_name\":\"SessionStart\"}" claude start
if [[ $RC -eq 0 && -z "$OUT" && ! -s "$LOG" ]]; then ok "start says nothing in a repo without PROGRESS.md or agent-harness.json"; else bad "start silent" "rc=$RC out=$OUT log=$(cat "$LOG")"; fi

touch "$REPO/PROGRESS.md"
run "{\"cwd\":\"$REPO/sub\",\"hook_event_name\":\"SessionStart\"}" claude start
if [[ $RC -eq 0 && "$OUT" == "preflight ran" && "$(cat "$LOG")" == "preflight $REPO " ]]; then ok "start runs preflight in a repo with PROGRESS.md"; else bad "start" "rc=$RC out=$OUT log=$(cat "$LOG")"; fi

mkdir -p "$TMP/above/proj" "$TMP/home/.agent-skills-setup"
git init -q "$TMP/above/proj"
echo "$TMP/above/proj" > "$TMP/home/.agent-skills-setup/target-repos.txt"
HOME="$TMP/home" run "{\"cwd\":\"$TMP/above\",\"hook_event_name\":\"SessionStart\"}" claude start
if [[ $RC -eq 0 && "$OUT" == "preflight ran" ]]; then ok "start runs preflight in a folder above a registered repo"; else bad "start above repo" "rc=$RC out=$OUT"; fi
HOME="$TMP/home" run "{\"cwd\":\"$TMP/plain\",\"hook_event_name\":\"SessionStart\"}" claude start
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "start stays silent in a folder with no registered repo below"; else bad "start plain" "rc=$RC out=$OUT"; fi

run "{\"tool_input\":{\"file_path\":\"$TMP/plain/a.sh\"}}" claude edit
if [[ $RC -eq 0 && "$(cat "$LOG")" == "sh-check $TMP/plain $TMP/plain/a.sh" ]]; then ok "an edit outside any repo runs in the file's folder"; else bad "no repo" "rc=$RC log=$(cat "$LOG")"; fi

run '{}' claude nope
if [[ $RC -eq 1 && "$ERR" == *usage* ]]; then ok "bad arguments print usage and do not block"; else bad "usage" "rc=$RC err=$ERR"; fi

# wire_global_hooks merges per-agent settings next to existing hooks, once, and removes only its own.
FH="$TMP/home"
mkdir -p "$FH/.claude" "$FH/.gemini/config" "$FH/.codex"
echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}' > "$FH/.claude/settings.json"
echo '{"polish-input":{"PreInvocation":[{"type":"command","command":"polish"}]}}' > "$FH/.gemini/config/hooks.json"
wire() { HOME="$FH" bash -c 'source "$0" >/dev/null 2>&1; for a in claude gemini codex kiro; do wire_global_hooks "$1" "$a" "${2:-}" >/dev/null 2>&1; done' "$SCRIPT_DIR/_lib.sh" "$SCRIPT_DIR/.." "$@"; }
wire; wire
rt="$FH/.agent-skills-setup/hooks"
got=$(python3 - "$FH" "$rt" <<'PY'
import json, sys
h, rt = sys.argv[1], sys.argv[2]
c = json.load(open(f"{h}/.claude/settings.json"))["hooks"]
g = json.load(open(f"{h}/.gemini/config/hooks.json"))
x = json.load(open(f"{h}/.codex/hooks.json"))["hooks"]
cmds = lambda gs: [k["command"] for e in gs for k in e.get("hooks", [e])]
print(cmds(c["Stop"]) == ["mine", f'bash "{rt}/global-hook.sh" claude stop'],
      cmds(c["SessionStart"]) == [f'bash "{rt}/global-hook.sh" claude start'],
      g["harness-global"]["Stop"] == [{"type": "command", "command": f'bash "{rt}/global-hook.sh" agy stop', "timeout": 120}],
      "polish-input" in g,
      x["PostToolUse"][0]["matcher"].startswith("apply_patch"))
PY
)
if [[ "$got" == "True True True True True" ]]; then ok "wire_global_hooks writes each agent's shape once, keeping existing hooks"; else bad "wire" "$got"; fi
wire --remove
got=$(python3 -c '
import json, sys
h = sys.argv[1]
c = json.load(open(h + "/.claude/settings.json"))["hooks"]
g = json.load(open(h + "/.gemini/config/hooks.json"))
print(sorted(c), "harness-global" in g, "polish-input" in g)' "$FH")
if [[ "$got" == "['Stop'] False True" ]]; then ok "--remove takes out only the global hooks"; else bad "remove" "$got"; fi

# A changed command of THIS runtime is replaced, not kept next to the new one;
# another installed harness repo's global hook (its own runtime dir) stays.
python3 - "$FH" "$rt" <<'PY'
import json, sys
h, rt = sys.argv[1], sys.argv[2]
e = lambda c: {"hooks": [{"type": "command", "command": c}]}
json.dump({"hooks": {"Stop": [e(f'bash "{rt}/global-hook.sh" claude stop --old'),
                              e('bash "/x/.other-rt/hooks/global-hook.sh" claude stop')]}},
          open(f"{h}/.claude/settings.json", "w"))
PY
wire
got=$(python3 -c '
import json, sys
c = json.load(open(sys.argv[1] + "/.claude/settings.json"))["hooks"]["Stop"]
print([k["command"] for x in c for k in x["hooks"]])' "$FH")
want="['bash \"/x/.other-rt/hooks/global-hook.sh\" claude stop', 'bash \"$rt/global-hook.sh\" claude stop']"
if [[ "$got" == "$want" ]]; then ok "a changed global hook command is replaced; another runtime's is kept"; else bad "prune" "$got"; fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
