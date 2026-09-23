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
if gh pr checks "$PR" --watch --fail-fast --interval 15; then
  echo "✅ All CI checks passed on PR #$PR."
  exit 0
else
  echo "" >&2
  echo "❌ CI checks failed on PR #$PR." >&2
  exit 1
fi

