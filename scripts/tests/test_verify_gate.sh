#!/usr/bin/env bash
# test_verify_gate.sh — common/verify-gate.sh: run the repo's verify commands at
# Stop when the turn changed relevant files, block on failure, log each run.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$(cd "$SCRIPT_DIR/../templates/hooks/common" && pwd)/verify-gate.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }
expect() { if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1" "want $2, got $3"; fi; }

repo() { # <verify json list> -> clone with an upstream, agent-harness.json committed and pushed
  local up cl
  up=$(mktemp -d "$TMP/up.XXXX"); cl=$(mktemp -d "$TMP/cl.XXXX")
  git -C "$up" init -q --bare
  git clone -q "$up" "$cl/w" 2>/dev/null
  printf '{"schema_version":1,"harness":{"source":"agent-skills-setup","version":"x"},"project":{"name":"r"},"state_files":[],"verify":%s,"hooks":[]}\n' "$1" > "$cl/w/agent-harness.json"
  mkdir -p "$cl/w/svc" "$cl/w/docs"; echo a > "$cl/w/svc/a.yaml"; echo d > "$cl/w/docs/d.md"
  git -C "$cl/w" add -A
  git -C "$cl/w" -c user.email=t@example.com -c user.name=t commit -qm init
  git -C "$cl/w" push -q -u origin "$(git -C "$cl/w" rev-parse --abbrev-ref HEAD)" 2>/dev/null
  echo "$cl/w"
}
gate() { # <repo> [gate copy] [HOME] -> sets RC OUT ERR
  OUT=$( cd "$1" && printf '%s' "${GATE_INPUT:-{\}}" | HOME="${3:-$TMP/nohome}" bash "${2:-$GATE}" 2>"$TMP/err" ); RC=$?
  ERR=$(cat "$TMP/err")
}
scoped=$(mktemp "$TMP/gate.XXXX"); sed "s|^RELEVANT_RE=.*|RELEVANT_RE='^svc/'|" "$GATE" > "$scoped"

R=$(repo '["echo one > ran1", "echo two > ran2"]')
gate "$R"
expect "nothing changed: exit 0" 0 "$RC"
if [[ "$OUT" == *SKIP* && ! -f "$R/ran1" ]]; then ok "nothing changed: SKIP, commands not run"; else bad "nothing changed" "out=$OUT"; fi

echo b >> "$R/docs/d.md"
gate "$R" "$scoped"
if [[ $RC -eq 0 && ! -f "$R/ran1" ]]; then ok "a change outside RELEVANT_RE does not run verify"; else bad "outside RELEVANT_RE" "rc=$RC"; fi

echo b >> "$R/svc/a.yaml"
gate "$R" "$scoped"
if [[ $RC -eq 0 && -f "$R/ran1" && -f "$R/ran2" ]]; then ok "a relevant change runs every verify command, passes"; else bad "relevant change" "rc=$RC err=$ERR"; fi

# shellcheck disable=SC2016  # the verify command's own $(seq) must stay unexpanded
R=$(repo '["true", "for i in $(seq 1 60); do echo line$i; done; exit 3", "echo never > ran3"]')
git -C "$R" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m unpushed
echo new > "$R/svc/new.yaml"
gate "$R"
expect "a failing verify blocks with exit 2" 2 "$RC"
if [[ "$ERR" == *"exit 3"* && "$ERR" == *line60* && "$ERR" != *"line10"$'\n'* && ! -f "$R/ran3" ]]; then
  ok "names the failing command, shows its last lines, stops there"
else
  bad "failure detail" "err=$ERR"
fi

# Logging: only with an installed harness.
H="$TMP/home"; mkdir -p "$H/.agent-skills-setup"
printf '{"commit":"abc","short":"abc","source_dir":"%s"}\n' "$TMP" > "$H/.agent-skills-setup/harness-version.json"
R=$(repo '["true"]'); echo c >> "$R/svc/a.yaml"
GATE_INPUT='{"session_id":"5a0ad1e4-6613-4db6-a27f-8e54a547759f"}' gate "$R" "" "$H"
log=$(find "$H/.agent-skills-setup/telemetry/w" -name 'verify-runs-*.jsonl' 2>/dev/null | head -1)
if [[ -n "$log" ]] && python3 -c '
import json,sys
rows=[json.loads(l) for l in open(sys.argv[1])]
r=rows[-1]
assert len(rows)==1 and r["result"]=="pass" and r["repo"]=="w" and r["commit"] and r["commands"][0]["cmd"]=="true" and r["commands"][0]["rc"]==0
assert isinstance(r["duration_s"], (int,float)) and r["ts"]
' "$log"; then ok "a run is logged centrally with result, commit and per-command rc"; else bad "central log" "log=$log $(cat "$log" 2>/dev/null)"; fi
if [[ -n "$log" ]] && python3 -c '
import json,sys
assert json.loads(open(sys.argv[1]).readlines()[-1])["session_id"]=="5a0ad1e4-6613-4db6-a27f-8e54a547759f"
' "$log"; then ok "the logged run names the session from the hook input"; else bad "session id" "$(tail -1 "$log" 2>/dev/null)"; fi
gate "$R" "" "$H"
if python3 -c '
import json,sys
assert json.loads(open(sys.argv[1]).readlines()[-1])["session_id"] is None
' "$log"; then ok "hook input without a session logs null"; else bad "no session id" "$(tail -1 "$log" 2>/dev/null)"; fi
gate "$R"   # no harness: must not create a log anywhere under the fake home
if [[ ! -d "$TMP/nohome/.agent-skills-setup/telemetry" ]]; then ok "no harness: nothing logged"; else bad "no harness" "log dir created"; fi

echo ""
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
