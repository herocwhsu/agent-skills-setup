#!/usr/bin/env bash
# k8s/checkov-guard.sh — Stop hook: Checkov IaC misconfiguration scan
# Copy to .claude/hooks/checkov-guard.sh in your repo
set -euo pipefail
command -v checkov &>/dev/null || { echo "  SKIP  checkov not installed (brew install checkov)"; exit 0; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WARN=0

echo "=== Checkov IaC scan ==="
# Skip checks: CKV_K8S_8/9/10 = liveness/readiness probes (optional), 28 = seccomp
if ! checkov -d "$REPO_ROOT" \
    --framework kubernetes \
    --quiet --compact \
    --skip-check CKV_K8S_8,CKV_K8S_9,CKV_K8S_10,CKV_K8S_28 \
    2>/dev/null; then
  echo "WARNING: checkov found IaC misconfigurations" >&2
  WARN=1
else
  echo "  OK  checkov"
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
