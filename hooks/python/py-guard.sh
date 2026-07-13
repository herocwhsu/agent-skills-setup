#!/usr/bin/env bash
# python/py-guard.sh — Stop hook: ruff check + bandit + pip-audit + pytest
# Edit APP_DIR to point at your Python app root
# Copy to .claude/hooks/py-guard.sh in your repo
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
APP_DIR="${APP_DIR:-$REPO_ROOT}"
WARN=0

echo "=== Ruff check ==="
if command -v ruff &>/dev/null; then
  ruff check "$APP_DIR/src" --quiet 2>/dev/null \
    || { echo "WARNING: ruff check failed" >&2; WARN=1; }
else
  echo "  SKIP  ruff not installed (pip install ruff)"
fi

echo ""
echo "=== Bandit ==="
if command -v bandit &>/dev/null && [[ -d "$APP_DIR/src" ]]; then
  bandit -r "$APP_DIR/src" -ll -q 2>/dev/null \
    || { echo "WARNING: bandit found security issues" >&2; WARN=1; }
else
  echo "  SKIP  bandit not installed (pip install bandit)"
fi

echo ""
echo "=== pip-audit ==="
if command -v pip-audit &>/dev/null && [[ -f "$APP_DIR/requirements.txt" ]]; then
  pip-audit -r "$APP_DIR/requirements.txt" -q 2>/dev/null \
    || { echo "WARNING: vulnerable dependencies found" >&2; WARN=1; }
fi

echo ""
echo "=== pytest ==="
if command -v pytest &>/dev/null; then
  (cd "$APP_DIR" && pytest -q --tb=short 2>/dev/null) \
    || { echo "WARNING: tests failed" >&2; WARN=1; }
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
