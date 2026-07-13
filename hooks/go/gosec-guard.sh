#!/usr/bin/env bash
# go/gosec-guard.sh — Stop hook: gosec security scan
# Copy to .claude/hooks/gosec-guard.sh in your repo
set -euo pipefail
command -v gosec &>/dev/null || { echo "  SKIP  gosec not installed (go install github.com/securego/gosec/v2/cmd/gosec@latest)"; exit 0; }

WARN=0
echo "=== gosec ==="
if ! gosec -quiet ./... 2>/dev/null; then
  echo "WARNING: gosec found security issues" >&2
  WARN=1
else
  echo "  OK  gosec"
fi
[[ $WARN -eq 0 ]] && exit 0 || exit 2
