#!/usr/bin/env bash
# common/semgrep-guard.sh — Stop hook: SAST scan
# Customize --config flags for your stack. Available rulesets:
#   p/python, p/typescript, p/javascript, p/bash, p/kubernetes,
#   p/secrets, p/owasp-top-ten, p/security-audit
# Copy to .claude/hooks/semgrep-guard.sh in your repo
set -euo pipefail
command -v semgrep &>/dev/null || { echo "  SKIP  semgrep not installed (brew install semgrep)"; exit 0; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WARN=0

echo "=== Semgrep SAST ==="
# Edit --config flags to match your stack
if ! semgrep scan \
    --config "p/secrets" \
    --error --quiet \
    --exclude "node_modules,__pycache__,.venv,dist,.git" \
    "$REPO_ROOT" 2>/dev/null; then
  echo "WARNING: semgrep found issues" >&2
  WARN=1
else
  echo "  OK  semgrep"
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
