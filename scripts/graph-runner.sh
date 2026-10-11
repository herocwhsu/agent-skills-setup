#!/usr/bin/env bash
# graph-runner.sh — Portable CLI wrapper for scripts/graph_runner.py (feat-060)
#
# Compatible with macOS /bin/bash 3.2 and Linux environments.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PYTHON="python3"
if [[ -f "$REPO_DIR/.venv/bin/python3" ]]; then
  PYTHON="$REPO_DIR/.venv/bin/python3"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v /usr/bin/python3 >/dev/null 2>&1; then
  PYTHON="/usr/bin/python3"
fi

exec "$PYTHON" "$REPO_DIR/scripts/graph_runner.py" --repo-dir "$REPO_DIR" "$@"
