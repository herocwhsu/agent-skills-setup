#!/usr/bin/env bash
# scripts/ci-watch.sh — watch CI checks for a PR to completion
#
# Usage:
#   bash scripts/ci-watch.sh [PR_NUMBER]
set -euo pipefail

command -v gh &>/dev/null || { echo "ERROR: gh CLI is not installed." >&2; exit 1; }

PR="${1:-}"
if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number -q .number 2>/dev/null || true)"
fi

if [[ -z "$PR" ]]; then
  echo "ERROR: no PR number provided and no active PR found on current branch." >&2
  exit 1
fi

echo "==> Watching CI checks for PR #$PR..."
TIMEOUT=900 # 15 minutes
INTERVAL=15
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  set +e
  gh pr checks "$PR" --fail-fast > /tmp/gh_watch_$$ 2>&1
  EXIT_CODE=$?
  set -e
  
  if [ "$EXIT_CODE" -eq 0 ]; then
    echo "✅ All CI checks passed on PR #$PR."
    rm -f /tmp/gh_watch_$$
    exit 0
  elif [ "$EXIT_CODE" -eq 8 ]; then
    # Pending
    sleep $INTERVAL
    ELAPSED=$(( ELAPSED + INTERVAL ))
  else
    echo "" >&2
    echo "❌ CI checks failed on PR #$PR:" >&2
    cat /tmp/gh_watch_$$ >&2
    rm -f /tmp/gh_watch_$$
    exit 1
  fi
done

echo "❌ Timeout waiting for PR #$PR CI checks to complete." >&2
rm -f /tmp/gh_watch_$$
exit 1
