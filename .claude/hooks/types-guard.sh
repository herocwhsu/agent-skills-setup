#!/usr/bin/env bash
# types-guard.sh — Stop/SubagentStop hook: block completion if mypy reports a
# type error. Exit 2 blocks; exit 0 allows.
#
# Whole-tree, never per-file: invoking mypy on a single file re-reports every
# error that lives in the modules it imports, so `mypy polish.py` shows 11
# errors that are all in polish_engine.py. Per-file counts triple the real
# total and point at the wrong file.
#
# Placed at Stop rather than PostToolUse deliberately: syntax checking is
# instant and belongs on every edit (py-check.sh), but a whole-tree type pass
# costs ~1s warm and ~6s cold, which is turn-scale, not keystroke-scale.
set -euo pipefail

# Overridable so a test can point at a throwaway repo. Without a seam the only
# testable case is "the real tree currently passes", which stops being a test
# the moment the tree is clean.
REPO_DIR="${TYPES_GUARD_REPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Skip rather than crash when the tool is absent, matching the repo's hook
# convention — but say so out loud. A silent skip would look identical to a
# passing gate on a host that never had mypy installed.
if ! command -v mypy >/dev/null 2>&1; then
  echo "  SKIP  mypy not installed (pip install mypy)"
  exit 0
fi

# `command -v` is not proof the tool runs: a pyenv shim resolves while pointing
# at an interpreter that never had the package, and exits 127 when invoked.
if ! mypy --version >/dev/null 2>&1; then
  echo "  SKIP  mypy is on PATH but fails to run (broken shim?)" >&2
  exit 0
fi

cd "$REPO_DIR"

files=$(git ls-files '*.py' 2>/dev/null)
[[ -z "$files" ]] && exit 0

if ! out=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 mypy 2>&1); then
  {
    echo "Blocked: mypy reported type errors:"
    printf '%s\n' "$out"
  } >&2
  exit 2
fi

exit 0
