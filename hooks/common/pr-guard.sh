#!/usr/bin/env bash
# common/pr-guard.sh — Stop hook: PR CI check verification
# If there is an open PR on the current branch, verifies that all CI checks pass.
# Blocks completion with exit code 2 if any CI checks fail.
# Copy to .claude/hooks/pr-guard.sh in your repo
set -euo pipefail

command -v gh &>/dev/null || { echo "  SKIP  gh CLI not installed"; exit 0; }

# Check if current directory is a git repository
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# Check if current branch is set and not default main/master
CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi

PR_NUMBER="$(gh pr view --json number,state -q 'select(.state=="OPEN") | .number' 2>/dev/null || true)"
if [[ -z "$PR_NUMBER" ]]; then
  # No open PR on this branch
  exit 0
fi

echo "=== PR CI Check Guard (PR #$PR_NUMBER) ==="

# Watch checks with timeout and fail-fast
TIMEOUT=900 # 15 minutes
INTERVAL=15
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  set +e
  gh pr checks "$PR_NUMBER" --fail-fast > /tmp/gh_checks_$$ 2>&1
  EXIT_CODE=$?
  set -e
  
  if [ "$EXIT_CODE" -eq 0 ]; then
    echo "  OK  all PR #$PR_NUMBER checks passed"
    rm -f /tmp/gh_checks_$$
    exit 0
  elif [ "$EXIT_CODE" -eq 8 ]; then
    # Pending
    sleep $INTERVAL
    ELAPSED=$(( ELAPSED + INTERVAL ))
  else
    # Failed or error
    echo "" >&2
    echo "❌ PR #$PR_NUMBER CI checks failed:" >&2
    cat /tmp/gh_checks_$$ >&2
    rm -f /tmp/gh_checks_$$
    echo "" >&2
    echo "Please diagnose the failure, fix the code, repush, and verify before marking complete." >&2
    exit 2
  fi
done

echo "❌ Timeout waiting for PR #$PR_NUMBER CI checks to complete." >&2
rm -f /tmp/gh_checks_$$
exit 2
