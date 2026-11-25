#!/usr/bin/env bash
# Tests for find_skill_dir in lib/lib.sh.
#
# Recipes cannot hard-code ~/.claude/skills: the same skill is installed under
# four agent dirs and only the selected agents have it. find_skill_dir lets a
# recipe ask "where is infra/ups on this host" without naming an agent.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_DIR/lib/lib.sh"
[[ -f "$LIB" ]] || { echo "FAIL: lib.sh not found at $LIB"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

fails=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "OK: $label"
  else
    echo "FAIL: $label"
    echo "      expected: $expected"
    echo "      actual:   $actual"
    fails=$((fails + 1))
  fi
}

# run_find <home> <skill> [CODEX_HOME]  -> prints "<stdout>|<exit>"
run_find() {
  local home="$1" skill="$2" codex="${3:-}" out rc=0
  out=$(HOME="$home" CODEX_HOME="$codex" bash -c 'source "$1"; find_skill_dir "$2"' _ "$LIB" "$skill" 2>/dev/null) || rc=$?
  echo "$out|$rc"
}

for agent_dir in .kiro/skills .claude/skills .codex/skills .gemini/antigravity-cli/skills; do
  h="$TMP/home-${agent_dir//\//_}"
  mkdir -p "$h/$agent_dir/infra/ups"
  check "finds a skill installed only for $agent_dir" "$h/$agent_dir/infra/ups|0" "$(run_find "$h" infra/ups)"
done

h="$TMP/home-none"
mkdir -p "$h"
check "missing skill returns 1 with empty stdout" "|1" "$(run_find "$h" infra/ups)"

h="$TMP/home-codexhome"
mkdir -p "$h" "$TMP/elsewhere/skills/infra/ups"
check "honours CODEX_HOME" "$TMP/elsewhere/skills/infra/ups|0" "$(run_find "$h" infra/ups "$TMP/elsewhere")"

h="$TMP/home-two"
mkdir -p "$h/.kiro/skills/infra/ups" "$h/.claude/skills/infra/ups"
check "same skill under two agents: first in kiro, claude, codex, antigravity order" "$h/.kiro/skills/infra/ups|0" "$(run_find "$h" infra/ups)"

h="$TMP/home-partial"
mkdir -p "$h/.claude/skills/infra"
check "group dir without the subcommand does not match" "|1" "$(run_find "$h" infra/ups)"

h="$TMP/home-args"
mkdir -p "$h/.claude/skills/a/b"
check "empty argument is rejected, not the skills root" "|1" "$(run_find "$h" "")"
check "'..' in the argument is rejected" "|1" "$(run_find "$h" a/b/../..)"

if [[ "$fails" -gt 0 ]]; then
  echo "$fails test(s) failed"
  exit 1
fi
echo "All find_skill_dir tests passed"
