#!/usr/bin/env bash
# go/govulncheck-guard.sh — Stop hook: govulncheck dependency vulnerability scan
# Copy to .claude/hooks/govulncheck-guard.sh in your repo
set -euo pipefail
command -v govulncheck &>/dev/null || { echo "  SKIP  govulncheck not installed (go install golang.org/x/vuln/cmd/govulncheck@latest)"; exit 0; }

WARN=0
echo "=== govulncheck ==="
if ! govulncheck ./... 2>/dev/null; then
  echo "WARNING: govulncheck found vulnerabilities called in code" >&2
  WARN=1
else
  echo "  OK  govulncheck"
fi
[[ $WARN -eq 0 ]] && exit 0 || exit 2
