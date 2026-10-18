#!/usr/bin/env bash
# Installed runtime files are copies, not symlinks; lib.sh and _store.sh drifted
# from the repo once without anything noticing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
GUARD="$REPO_DIR/.claude/hooks/runtime-drift-guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }
expect() { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "expected $2, got $3"; }
rc() { set +e; HOME="$TMP/home" RUNTIME_DRIFT_GUARD_RUNTIME_DIR="${1:-}" bash "$GUARD" >"$TMP/out" 2>&1; echo $?; set -e; }
said() { grep -q "$1" "$TMP/out" && echo yes || echo no; }

mkdir -p "$TMP/home"
expect "absent runtime is a skip" 0 "$(rc "$TMP/none")"
expect "skip says SKIP" yes "$(said SKIP)"

# Built by the real installer, so a file added to install but not the guard fails here.
HOME="$TMP/home" bash -c 'source "$1/scripts/_lib.sh" && install_runtime_dir "$1"' _ "$REPO_DIR" >/dev/null
source "$REPO_DIR/scripts/_lib.sh"
RT="$TMP/home/.agent-skills-setup"
expect "installed copies pass" 0 "$(rc)"

echo "# drift" >> "$RT/_store.sh"
expect "drifted _store.sh blocks" 2 "$(rc)"
expect "names the drifted file" yes "$(said _store.sh)"
cp "$REPO_DIR/scripts/credentials/_store.sh" "$RT/_store.sh"

rm "$RT/outside_agent.py"
expect "missing copy blocks" 2 "$(rc)"
expect "names the missing file" yes "$(said outside_agent.py)"

# Installed statusline scripts. Built in a fake repo on main so the result never depends on
# the branch or worktree this repo happens to be in. The gate flags only what install.sh
# can repair: a copy that settings.json names, for an agent in the saved selection.
cp "$REPO_DIR/scripts/credentials/_store.sh" "$RT/_store.sh"
cp "$REPO_DIR/scripts/outside_agent.py" "$RT/outside_agent.py"
expect "baseline passes again" 0 "$(rc)"

make_fake() {  # <dir> <branch>
  mkdir -p "$1/harness/guards" "$1/scripts" "$1/config"
  cp "$REPO_DIR/harness/guards/runtime-drift-guard.sh" "$1/harness/guards/"
  cp "$REPO_DIR/scripts/_lib.sh" "$1/scripts/"
  cp "$REPO_DIR/config/statusline-command.sh" "$1/config/"
  while read -r src dst; do mkdir -p "$1/$(dirname "$src")"; cp "$REPO_DIR/$src" "$1/$src"; done < <(runtime_files)
  git -C "$1" init -q -b "$2"
}
FAKE="$TMP/fake"; make_fake "$FAKE" main
SL="$FAKE/config/statusline-command.sh"
FRT="$TMP/fake-rt"   # in sync with the fake repo and selecting every agent, so only the statusline part can differ
mkdir -p "$FRT"
while read -r src dst; do mkdir -p "$(dirname "$FRT/$dst")"; cp "$FAKE/$src" "$FRT/$dst"; done < <(runtime_files)
echo "all" > "$FRT/agent-selection.txt"
frc() { set +e; HOME="$TMP/home" RUNTIME_DRIFT_GUARD_RUNTIME_DIR="${RTDIR:-$FRT}" bash "$FAKE/harness/guards/runtime-drift-guard.sh" >"$TMP/out" 2>&1; echo $?; set -e; }
AGY="$TMP/home/.gemini/antigravity-cli"; CLD="$TMP/home/.claude"
mkdir -p "$AGY" "$CLD"
point() { printf '{"statusLine":{"type":"command","command":"bash %s/statusline-command.sh","enabled":true}}\n' "$1" > "$1/settings.json"; }

point "$AGY"; cp "$SL" "$AGY/statusline-command.sh"
expect "matching AGY statusline copy passes" 0 "$(frc)"
echo "# stale" >> "$AGY/statusline-command.sh"
expect "stale AGY statusline copy blocks" 2 "$(frc)"
expect "names the AGY statusline copy" yes "$(said antigravity-cli/statusline-command.sh)"
rm "$AGY/statusline-command.sh"
expect "missing AGY statusline copy blocks" 2 "$(frc)"
cp "$SL" "$AGY/statusline-command.sh"; echo "# stale" >> "$AGY/statusline-command.sh"

printf '{"statusLine":{"type":"command","command":"node custom.js"}}\n' > "$AGY/settings.json"
expect "foreign AGY statusLine is not flagged" 0 "$(frc)"
printf '{"statusLine":{"command":"node custom.js"},"env":{"X":"%s/statusline-command.sh"}}\n' "$AGY" > "$AGY/settings.json"
expect "our path only in another key is not flagged" 0 "$(frc)"
printf '{"statusLine":{"command":"bash %s/statusline-command.sh.bak"}}\n' "$AGY" > "$AGY/settings.json"
expect "a longer path (.sh.bak) is not flagged" 0 "$(frc)"
printf '{"statusLine":{"command":"bash %s/statusline-command.sh"' "$AGY" > "$AGY/settings.json"
expect "truncated settings are not flagged" 0 "$(frc)"
printf '[]' > "$AGY/settings.json"
expect "settings that are not an object are not flagged" 0 "$(frc)"
printf '{"statusLine":"bash %s/statusline-command.sh"}\n' "$AGY" > "$AGY/settings.json"
expect "a statusLine that is not an object is not flagged" 0 "$(frc)"
printf '{"statusLine":{"command":"bash ~/.gemini/antigravity-cli/statusline-command.sh"}}\n' > "$AGY/settings.json"
expect "tilde form is not flagged (install_statusline does not refresh it either)" 0 "$(frc)"
rm -f "$AGY/settings.json"
expect "no AGY settings is not flagged" 0 "$(frc)"
rm -rf "$AGY"
expect "AGY not installed is not flagged" 0 "$(frc)"

point "$CLD"; cp "$SL" "$CLD/statusline-command.sh"
expect "matching Claude statusline copy passes" 0 "$(frc)"
echo "# stale" >> "$CLD/statusline-command.sh"
expect "stale Claude statusline copy blocks" 2 "$(frc)"
expect "names the Claude statusline copy" yes "$(said /.claude/statusline-command.sh)"
printf '{"statusLine":{"type":"command","command":"node /x/claude-hud/dist/index.js"}}\n' > "$CLD/settings.json"
expect "claude-hud statusLine is not flagged" 0 "$(frc)"
point "$CLD"; rm -rf "$FRT"
expect "absent runtime dir still checks the statusline copies" 2 "$(frc)"
expect "and still says SKIP for the runtime part" yes "$(said SKIP)"

# the saved agent selection decides which agents install.sh refreshes
mkdir -p "$TMP/sel"; RTDIR="$TMP/sel"
while read -r src dst; do mkdir -p "$(dirname "$TMP/sel/$dst")"; cp "$FAKE/$src" "$TMP/sel/$dst"; done < <(runtime_files)
echo "gemini" > "$TMP/sel/agent-selection.txt"
cp "$SL" "$CLD/statusline-command.sh"
expect "control: the runtime part is clean and a matching copy passes" 0 "$(frc)"
echo "# stale" >> "$CLD/statusline-command.sh"
expect "claude outside the saved selection is not flagged" 0 "$(frc)"
expect "and the reason is the selection, not a skipped runtime part" no "$(said 'runtime copies')"
echo "claude" > "$TMP/sel/agent-selection.txt"
expect "claude in the saved selection is flagged" 2 "$(frc)"
echo "claude,gemini" > "$TMP/sel/agent-selection.txt"
expect "a list selection includes claude" 2 "$(frc)"
echo "all" > "$TMP/sel/agent-selection.txt"
expect "selection all includes claude" 2 "$(frc)"
RTDIR=""

# no saved selection: a bare install.sh selects claude only, so gemini is not flagged
rm -f "$TMP/sel/agent-selection.txt"; RTDIR="$TMP/sel"
mkdir -p "$AGY"; point "$AGY"; cp "$SL" "$AGY/statusline-command.sh"; echo "# stale" >> "$AGY/statusline-command.sh"
point "$CLD"; cp "$SL" "$CLD/statusline-command.sh"
expect "no saved selection: a stale gemini copy is not flagged" 0 "$(frc)"
echo "# stale" >> "$CLD/statusline-command.sh"
expect "no saved selection: a stale claude copy is flagged" 2 "$(frc)"
: > "$TMP/sel/agent-selection.txt"
expect "an empty selection file behaves like none" 2 "$(frc)"
RTDIR=""; rm -rf "$AGY"

# the gate must agree with install_statusline, which finds the copy by a literal match of its path in
# settings.json. A HOME that JSON escapes (wire_hook writes é) is then not flagged, because
# install_statusline cannot repair it either; an unescaped HOME is.
UH="$TMP/h$(printf '\303\251')llo"; mkdir -p "$UH/.claude"
python3 - "$UH" <<'EOF'
import json, sys
h = sys.argv[1]
open(h + "/.claude/settings.json", "w").write(json.dumps({"statusLine": {"type": "command", "command": f"bash {h}/.claude/statusline-command.sh", "enabled": True}}))
EOF
cp "$SL" "$UH/.claude/statusline-command.sh"; echo "# stale" >> "$UH/.claude/statusline-command.sh"
set +e; HOME="$UH" RUNTIME_DRIFT_GUARD_RUNTIME_DIR="$FRT" bash "$FAKE/harness/guards/runtime-drift-guard.sh" >"$TMP/out" 2>&1; r=$?; set -e
( HOME="$UH"; export HOME; source "$REPO_DIR/scripts/_lib.sh"; install_statusline claude "$FAKE" >/dev/null 2>&1 ) || true
set +e; HOME="$UH" RUNTIME_DRIFT_GUARD_RUNTIME_DIR="$FRT" bash "$FAKE/harness/guards/runtime-drift-guard.sh" >"$TMP/out" 2>&1; r2=$?; set -e
expect "after install_statusline the gate agrees with it for an escaped HOME" "$r2" "$([[ $r2 -eq 0 ]] && echo 0 || echo "$r2")"
expect "an escaped HOME that install_statusline cannot repair is not a block" 0 "$r"

# nothing the repair cannot clear: other branch, linked worktree, no source file, no HOME
OTHER="$TMP/other"; make_fake "$OTHER" feature
set +e; HOME="$TMP/home" RUNTIME_DRIFT_GUARD_RUNTIME_DIR="$FRT" bash "$OTHER/harness/guards/runtime-drift-guard.sh" >"$TMP/out" 2>&1; r=$?; set -e
expect "a non-default branch is not flagged (install.sh refuses it)" 0 "$r"
git -C "$FAKE" -c user.name=t -c user.email=t@e.invalid commit -q --allow-empty -m init
git -C "$FAKE" worktree add -q "$TMP/wt" -b wtbranch
mkdir -p "$TMP/wt/harness/guards" "$TMP/wt/scripts" "$TMP/wt/config"
cp "$FAKE/harness/guards/runtime-drift-guard.sh" "$TMP/wt/harness/guards/"; cp "$FAKE/scripts/_lib.sh" "$TMP/wt/scripts/"; cp "$SL" "$TMP/wt/config/"
set +e; HOME="$TMP/home" RUNTIME_DRIFT_GUARD_RUNTIME_DIR="$FRT" bash "$TMP/wt/harness/guards/runtime-drift-guard.sh" >"$TMP/out" 2>&1; r=$?; set -e
expect "a linked worktree is not flagged (install.sh refuses it)" 0 "$r"
mv "$SL" "$TMP/sl.aside"
expect "a repo without config/statusline-command.sh is not flagged" 0 "$(frc)"
mv "$TMP/sl.aside" "$SL"
expect "back to flagged with the source restored" 2 "$(frc)"
set +e; env -u HOME RUNTIME_DRIFT_GUARD_RUNTIME_DIR="$FRT" bash "$FAKE/harness/guards/runtime-drift-guard.sh" >"$TMP/out" 2>&1; r=$?; set -e
expect "unset HOME with a runtime dir given does not crash the statusline part" 0 "$r"

echo "test_runtime_drift_guard: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
