#!/usr/bin/env bash
# common/secret-scan.sh — Stop hook: gitleaks + osv-scanner
# Copy to .claude/hooks/secret-scan.sh in your repo
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WARN=0

echo "=== Gitleaks secret scan ==="
if command -v gitleaks &>/dev/null; then
  if ! gitleaks detect --source "$REPO_ROOT" --no-git --redact -q 2>/dev/null; then
    echo "WARNING: gitleaks found potential secrets — review before committing" >&2
    WARN=1
  else
    echo "  OK  gitleaks"
  fi
else
  echo "  SKIP  gitleaks not installed (brew install gitleaks)"
fi

echo ""
echo "=== OSV dependency scan ==="
if command -v osv-scanner &>/dev/null; then
  if ! osv-scanner scan --recursive "$REPO_ROOT" -q 2>/dev/null; then
    echo "WARNING: osv-scanner found vulnerable dependencies" >&2
    WARN=1
  else
    echo "  OK  osv-scanner"
  fi
else
  echo "  SKIP  osv-scanner not installed (brew install osv-scanner)"
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
