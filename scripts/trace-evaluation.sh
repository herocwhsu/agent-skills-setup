#!/usr/bin/env bash
# trace-evaluation.sh — Portable CLI wrapper for scripts/trace_evaluation.py
#
# Captures and inspects state layer evaluation telemetry, token bloat metrics,
# and historical trends across commits.
#
# Usage:
#   bash scripts/trace-evaluation.sh                  # Record snapshot to docs/telemetry/evaluation-trace.jsonl
#   bash scripts/trace-evaluation.sh --trend          # Render historical trend table
#   bash scripts/trace-evaluation.sh --check-thresholds # Check for state layer bloat
#   bash scripts/trace-evaluation.sh --json           # Output current snapshot as JSON
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="python3"

if [[ -x "$REPO_DIR/.venv/bin/python3" ]]; then
  PYTHON="$REPO_DIR/.venv/bin/python3"
fi

exec "$PYTHON" "$REPO_DIR/scripts/trace_evaluation.py" --repo-dir "$REPO_DIR" "$@"
