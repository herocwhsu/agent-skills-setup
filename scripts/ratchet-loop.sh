#!/usr/bin/env bash
# ratchet-loop.sh — Portable CLI wrapper for scripts/ratchet_loop_runner.py (feat-058)
#
# Runs autonomous ratchet loops with Maker/Checker separation, automated verification,
# independent review evaluation, and automatic rollback on regression.
#
# Usage:
#   bash scripts/ratchet-loop.sh --demo                   # Run synthetic demo loop
#   bash scripts/ratchet-loop.sh --active-feature         # Load current active feature from feature_list.json
#   bash scripts/ratchet-loop.sh --goal docs/goals/<g>.md # Run or inspect a goal specification
#   bash scripts/ratchet-loop.sh --review-diff            # Run outside-agent review on working tree diff
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="python3"

if [[ -x "$REPO_DIR/.venv/bin/python3" ]]; then
  PYTHON="$REPO_DIR/.venv/bin/python3"
fi

exec "$PYTHON" "$REPO_DIR/scripts/ratchet_loop_runner.py" --repo-dir "$REPO_DIR" "$@"
