#!/usr/bin/env bash
# init.sh — standard startup/verification entrypoint for agents working in this
# repo. Delegates to scripts/harness-verify.sh rather than re-implementing the
# gates: that script is already the single source of truth (same checks run as
# Stop hooks), and a second implementation here would drift from it the first
# time either one changed. See AGENTS.md for the rest of the startup workflow.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# A fresh clone has no .venv, and without it the types gate fails on missing
# third-party stubs while the tests gate quietly falls back to ambient python3.
if [[ ! -d "$REPO_DIR/.venv" && -f "$REPO_DIR/requirements-dev.txt" ]]; then
  if [[ -f "$REPO_DIR/.python-version" ]]; then
    pinned=$(tr -d '[:space:]' < "$REPO_DIR/.python-version")
    actual=$(python3 --version 2>&1 | awk '{print $2}')
    if [[ "$actual" != "$pinned" ]]; then
      echo "init.sh: python3 is $actual but .python-version pins $pinned; put $pinned first on PATH (pyenv: pyenv install $pinned) and re-run" >&2
      exit 1
    fi
  fi
  echo "init.sh: no .venv, building it from requirements-dev.txt (about a minute)"
  # An interrupted build must not leave a .venv the next run would trust.
  trap 'rm -rf "$REPO_DIR/.venv"; exit 130' INT TERM HUP
  if ! { python3 -m venv "$REPO_DIR/.venv" \
         && "$REPO_DIR/.venv/bin/pip" install -q -r "$REPO_DIR/requirements-dev.txt"; }; then
    rm -rf "$REPO_DIR/.venv"
    echo "init.sh: .venv build failed; fix the error above and re-run" >&2
    exit 1
  fi
  trap - INT TERM HUP
fi

exec bash "$REPO_DIR/scripts/harness-verify.sh" "$@"
