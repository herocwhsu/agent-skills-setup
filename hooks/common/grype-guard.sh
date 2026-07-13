#!/usr/bin/env bash
# common/grype-guard.sh — Stop hook: CVE scan on filesystem/images
# Customize SCAN_TARGETS for your repo layout
# Copy to .claude/hooks/grype-guard.sh in your repo
set -euo pipefail
command -v grype &>/dev/null || { echo "  SKIP  grype not installed (brew install grype)"; exit 0; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WARN=0

echo "=== Grype CVE scan ==="
# Edit SCAN_TARGETS to match your repo (dirs with requirements.txt or package.json)
SCAN_TARGETS=("$REPO_ROOT")

for target in "${SCAN_TARGETS[@]}"; do
  [[ -d "$target" ]] || continue
  echo "  scanning $target"
  if ! grype "dir:$target" --fail-on high --quiet --only-fixed 2>/dev/null; then
    echo "WARNING: HIGH+ CVEs found in $target (with available fixes)" >&2
    WARN=1
  else
    echo "  OK  $target"
  fi
done

[[ $WARN -eq 0 ]] && exit 0 || exit 2
