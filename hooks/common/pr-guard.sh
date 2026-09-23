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
echo "Watching CI checks for PR #$PR_NUMBER..."

if gh pr checks "$PR_NUMBER" --watch --fail-fast --interval 15; then
  echo "  OK  all PR #$PR_NUMBER checks passed"
  exit 0
else
  echo "" >&2
  echo "❌ PR #$PR_NUMBER CI checks failed." >&2
  echo "Please diagnose the failure, fix the code, repush, and verify before marking complete." >&2
  exit 2
fi

