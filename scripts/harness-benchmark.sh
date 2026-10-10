#!/usr/bin/env bash
# scripts/harness-benchmark.sh - Shell wrapper for harness self-benchmark runner
# macOS /bin/bash 3.2 compatible.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VENV_PY="$REPO_ROOT/.venv/bin/python3"
if [ -x "$VENV_PY" ]; then
  PYTHON="$VENV_PY"
else
  PYTHON="python3"
fi

exec "$PYTHON" "$SCRIPT_DIR/harness_benchmark.py" "$@"
