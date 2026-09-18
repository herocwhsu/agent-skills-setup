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

# Prefer this repo's own venv (built from requirements-dev.txt, the manifest
# osv-scanner actually scans) over whatever mypy happens to be on PATH. Falls
# back to bare `mypy` only when .venv was never set up at all — a .venv
# directory that DOES exist must work correctly, or we fail loud. A `-x`
# check alone proves only "executable", not "the right interpreter" or "still
# has the package" — a stale/broken venv silently degrading to ambient
# tooling would look identical to "no venv was ever created."
MYPY="mypy"
VENV_DIR="$REPO_DIR/.venv"
if [[ -d "$VENV_DIR" ]]; then
  VENV_MYPY="$VENV_DIR/bin/mypy"
  VENV_PY="$VENV_DIR/bin/python3"
  if [[ ! -x "$VENV_MYPY" || ! -x "$VENV_PY" ]]; then
    echo "Blocked: .venv exists but is missing python3/mypy. Rebuild: rm -rf .venv && python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt" >&2
    exit 2
  fi
  if [[ -f "$REPO_DIR/.python-version" ]]; then
    pinned=$(tr -d '[:space:]' < "$REPO_DIR/.python-version")
    actual=$("$VENV_PY" --version 2>&1 | awk '{print $2}')
    if [[ "$actual" != "$pinned" ]]; then
      echo "Blocked: .venv is Python $actual but .python-version pins $pinned — rebuild: rm -rf .venv && python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt" >&2
      exit 2
    fi
  fi
  MYPY="$VENV_MYPY"
fi

# Skip rather than crash when the tool is absent, matching the repo's hook
# convention — but say so out loud. A silent skip would look identical to a
# passing gate on a host that never had mypy installed.
if ! command -v "$MYPY" >/dev/null 2>&1; then
  echo "  SKIP  mypy not installed (pip install mypy, or set up .venv per requirements-dev.txt)"
  exit 0
fi

# `command -v` is not proof the tool runs: a pyenv shim resolves while pointing
# at an interpreter that never had the package, and exits 127 when invoked.
if ! "$MYPY" --version >/dev/null 2>&1; then
  echo "  SKIP  mypy is on PATH but fails to run (broken shim?)" >&2
  exit 0
fi

cd "$REPO_DIR"

files=$(git ls-files '*.py' 2>/dev/null)
[[ -z "$files" ]] && exit 0

if ! out=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 "$MYPY" 2>&1); then
  {
    echo "Blocked: mypy reported type errors:"
    printf '%s\n' "$out"
  } >&2
  exit 2
fi

exit 0
