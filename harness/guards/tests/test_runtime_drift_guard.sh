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
RT="$TMP/home/.agent-skills-setup"
expect "installed copies pass" 0 "$(rc)"

echo "# drift" >> "$RT/_store.sh"
expect "drifted _store.sh blocks" 2 "$(rc)"
expect "names the drifted file" yes "$(said _store.sh)"
cp "$REPO_DIR/scripts/credentials/_store.sh" "$RT/_store.sh"

rm "$RT/outside_agent.py"
expect "missing copy blocks" 2 "$(rc)"
expect "names the missing file" yes "$(said outside_agent.py)"

echo "test_runtime_drift_guard: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
