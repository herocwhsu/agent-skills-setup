#!/usr/bin/env bash
# get-changed-files.sh — identify modified, staged, and untracked files
# Compatible with macOS /bin/bash 3.2.
# Usage: bash scripts/get-changed-files.sh [base_ref]
set -euo pipefail

REPO_DIR="${GET_CHANGED_REPO_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_DIR"

BASE_REF="${1:-}"

if [[ -n "$BASE_REF" ]]; then
  # Compare against a specific base reference (e.g. HEAD, origin/main, or merge-base)
  {
    git diff --name-only "$BASE_REF" 2>/dev/null || true
    git ls-files --others --exclude-standard 2>/dev/null || true
  } | sed '/^[[:space:]]*$/d' | sort -u
else
  # Working tree: staged + unstaged + untracked non-ignored
  {
    git diff --name-only --cached 2>/dev/null || true
    git diff --name-only 2>/dev/null || true
    git ls-files --others --exclude-standard 2>/dev/null || true
  } | sed '/^[[:space:]]*$/d' | sort -u
fi
