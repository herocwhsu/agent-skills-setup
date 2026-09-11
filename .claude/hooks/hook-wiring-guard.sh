#!/usr/bin/env bash
# hook-wiring-guard.sh — Stop/SubagentStop hook: block completion if a shipped
# hook.json could not work once installed — an unknown event name that is never
# dispatched, a command whose target file is absent, or a hardcoded path where
# ${AGENT_SKILLS_DIR} belongs. Each of those presents at runtime as a hook that
# simply never fires, with nothing logged anywhere. Exit 2 blocks; exit 0 allows.
#
# Repo side only, deliberately. Whether a hook is *wired* on this machine is
# machine state that no code edit can fix, so blocking a turn on it would be
# unfixable from here; harness-verify.sh passes the real settings.json instead.
set -euo pipefail

# Two separate paths, deliberately. The checker always resolves from this script's
# own location, which never moves relative to the repo; only the *tree under test*
# is overridable. Deriving both from one overridable variable makes the failure
# path untestable: pointing it at a throwaway tree also points it at a
# non-existent checker, so python3 exits non-zero for the wrong reason and the
# guard looks like it blocked correctly when it never ran the check at all.
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$REPO_DIR/scripts/hook-wiring-check.py"
TREE="${HOOK_WIRING_GUARD_REPO_DIR:-$REPO_DIR}"

if [[ ! -f "$CHECK" ]]; then
  echo "Blocked: hook-wiring-check.py missing at $CHECK" >&2
  exit 2
fi

if ! out=$(python3 "$CHECK" "$TREE" 2>&1); then
  {
    echo "Blocked: a shipped hook.json would not work once installed:"
    printf '%s\n' "$out"
  } >&2
  exit 2
fi

exit 0
