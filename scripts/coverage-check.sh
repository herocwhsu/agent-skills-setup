#!/usr/bin/env bash
# coverage-check.sh — report subcommands that ship code but nothing exercises it.
#
# Usage: bash scripts/coverage-check.sh [skills-dir]
#
# Only code-bearing subcommands (those shipping a .sh or .py outside tests/) can
# have a test gap. The majority of subcommands are prompt-only markdown — there
# is no code to run, so reporting them as UNTESTED buries the real gaps. Those
# are counted separately instead.
#
# A code-bearing subcommand counts as covered only when it owns a test file.
# A group-level test that greps a sibling IMPL.md does not count: it asserts on
# prose, which says nothing about whether the shipped script runs.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="${1:-$REPO_DIR/skills}"

untested=0
prompt_only=0

while IFS= read -r -d '' impl; do
  dir="$(dirname "$impl")"

  # Prompt-only subcommands have no executable payload to exercise.
  if ! find "$dir" \( -name "*.sh" -o -name "*.py" \) -not -path "*/tests/*" 2>/dev/null | grep -q .; then
    prompt_only=$((prompt_only + 1))
    continue
  fi

  if ! find "$dir" \( -name "test_*.sh" -o -name "test_*.py" \) 2>/dev/null | grep -q .; then
    echo "  UNTESTED  $impl"
    untested=$((untested + 1))
  fi
done < <(find "$SKILLS_DIR" -name "IMPL.md" -print0 | sort -z)

echo "Coverage: $untested code-bearing subcommand(s) without tests, $prompt_only prompt-only"
[[ $untested -eq 0 ]]
