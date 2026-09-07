#!/usr/bin/env bash
# credential-backend-guard.sh — Stop/SubagentStop hook: block completion if a
# credential dispatch in _store.sh does not handle every backend _os() can
# return. Exit 2 blocks; exit 0 allows.
#
# Each `case "$(_os)" in` is its own switch, so a missing branch falls through
# and the function returns 0 -- the caller sees success with nothing done. That
# shipped twice: list_credentials printed an empty listing and delete_credential
# reported a delete that never happened, both green on macOS (darwin) and red on
# a clean ubuntu runner (linux-file).
#
# Source-level rather than behavioural: the test suite covers what each backend
# does, but only over the backends a test thought to stub. This asserts the set
# itself is complete, so adding a backend to _os() cannot leave a dispatch
# behind.
set -euo pipefail

# Overridable so a test can point at a throwaway tree. Without a seam the only
# testable case is "the real tree currently passes", which stops being a test
# the moment the tree is clean.
REPO_DIR="${CREDENTIAL_BACKEND_GUARD_REPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

CHECKER="$REPO_DIR/scripts/credential-backend-check.py"
STORE="$REPO_DIR/scripts/credentials/_store.sh"

# Skip rather than crash when the pieces are absent, matching the repo's hook
# convention: a guard that cannot run is not a guard that failed.
[[ -f "$CHECKER" && -f "$STORE" ]] || exit 0

if ! out=$(python3 "$CHECKER" "$STORE" 2>&1); then
  {
    echo "Blocked: a credential dispatch does not handle every storage backend:"
    printf '%s\n' "$out"
  } >&2
  exit 2
fi

exit 0
