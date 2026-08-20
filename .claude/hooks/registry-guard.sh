#!/usr/bin/env bash
# registry-guard.sh — Stop/SubagentStop hook: block completion if
# registry.txt is malformed (missing SKILL.md, malformed plugin/github-skill
# entries, etc). Catches a broken registry before it's ever committed, not
# just when someone happens to run scripts/validate-registry.sh by hand.
# Exit 2 blocks (Claude Code re-reads stderr and can self-correct);
# exit 0 allows.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if ! out=$(bash "$REPO_DIR/scripts/validate-registry.sh" 2>&1); then
  echo "Blocked: registry.txt failed validation:" >&2
  echo "$out" >&2
  exit 2
fi

exit 0
