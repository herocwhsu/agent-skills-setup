#!/usr/bin/env bash
# skill-paths-guard.sh — Stop/SubagentStop hook: block completion if a skill's
# shell recipe builds a repo path from a variable it never defines. Such a path
# expands to /scripts/... and cannot exist, so the recipe is dead as written
# while still reading as if it works. Exit 2 blocks; exit 0 allows.
#
# Whole-repo rather than PostToolUse: the check reads every *.md under skills/
# in one pass (~50ms), and a per-edit run would re-scan the tree on every
# keystroke-scale edit for a class of defect that only matters at turn end.
set -euo pipefail

# Overridable so a test can point at a throwaway tree. Without a seam the only
# testable case is "the real tree currently passes", which stops being a test
# the moment the tree is clean.
REPO_DIR="${SKILL_PATHS_GUARD_REPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

if ! out=$(python3 "$REPO_DIR/scripts/skill-path-var-check.py" "$REPO_DIR/skills" 2>&1); then
  {
    echo "Blocked: a skill shell block references an undefined repo path variable:"
    printf '%s\n' "$out"
  } >&2
  exit 2
fi

exit 0
