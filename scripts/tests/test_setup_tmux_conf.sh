#!/usr/bin/env bash
# Tests for scripts/setup-tmux-conf.sh (the tmux step of setup-host.sh).
#
# On macOS the tmux server runs in the GUI session, so panes can always reach
# the login keychain; but tmux copies SSH_CONNECTION into the session on an SSH
# attach, and agy then skips the keychain ("SSH session detected") and reports
# "not logged in". So on Darwin update-environment must leave SSH_CONNECTION
# out. On Linux agy's SSH rule is right (no unlocked keyring over SSH), so the
# tmux default must be left alone there.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_DIR/scripts/setup-tmux-conf.sh"
[[ -f "$SCRIPT" ]] || { echo "FAIL: setup-tmux-conf.sh not found at $SCRIPT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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

# run_as <os> <home>   run the step as if on <os>, against <home>/.tmux.conf
run_as() { HOME="$2" SETUP_TMUX_UNAME="$1" bash "$SCRIPT" > /dev/null; }
count() { grep -cF -- "$1" "$2" || true; }

# --- macOS: SSH_CONNECTION left out of update-environment
H="$TMP/mac"; mkdir -p "$H"
run_as Darwin "$H"
C="$H/.tmux.conf"
UE=$(grep '^set -g update-environment' "$C" || true)
check "darwin: update-environment set once"      1 "$(count 'set -g update-environment' "$C")"
check "darwin: SSH_CONNECTION not in the list"   0 "$(printf '%s' "$UE" | grep -c SSH_CONNECTION || true)"
check "darwin: SSH_AUTH_SOCK still updated"       1 "$(printf '%s' "$UE" | grep -c SSH_AUTH_SOCK || true)"
check "darwin: pbcopy yank"                       2 "$(count pbcopy "$C")"
check "darwin: mouse on"                          1 "$(count 'set -g mouse on' "$C")"

# --- running it again changes nothing
before=$(cat "$C")
run_as Darwin "$H"
check "darwin: idempotent"                        "$before" "$(cat "$C")"

# --- an existing config is kept, only missing lines are appended
H="$TMP/existing"; mkdir -p "$H"
printf 'set -g history-limit 50000\nset -g mouse on\n' > "$H/.tmux.conf"
run_as Darwin "$H"
check "existing: own line kept"                   1 "$(count 'set -g history-limit 50000' "$H/.tmux.conf")"
check "existing: mouse not duplicated"            1 "$(count 'set -g mouse on' "$H/.tmux.conf")"

# --- Linux: tmux default update-environment untouched
H="$TMP/linux"; mkdir -p "$H"
run_as Linux "$H"
check "linux: update-environment not set"         0 "$(count 'update-environment' "$H/.tmux.conf")"
check "linux: xclip yank"                         2 "$(count xclip "$H/.tmux.conf")"

if [[ $fails -gt 0 ]]; then echo "$fails failure(s)"; exit 1; fi
echo "All setup-tmux-conf tests passed."
