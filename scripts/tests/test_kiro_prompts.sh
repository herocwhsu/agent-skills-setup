#!/usr/bin/env bash
# Tests for install_kiro_prompts and uninstall_kiro_prompts in scripts/_lib.sh.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_DIR/scripts/_lib.sh"
[[ -f "$LIB" ]] || { echo "FAIL: _lib.sh not found at $LIB"; exit 1; }

# Source helper functions from _lib.sh
# shellcheck source=scripts/_lib.sh
source "$LIB"

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

MOCK_REPO="$TMP/repo"
MOCK_HOME="$TMP/home"
mkdir -p "$MOCK_REPO/agents/kiro/prompts" "$MOCK_HOME"

echo "User path is /Users/<user>/sample" > "$MOCK_REPO/agents/kiro/prompts/sample.md"

# Run install with mock HOME
HOME="$MOCK_HOME" install_kiro_prompts "$MOCK_REPO" >/dev/null

check "prompt copied to ~/.kiro/prompts" "true" "$([[ -f "$MOCK_HOME/.kiro/prompts/sample.md" ]] && echo true || echo false)"
check "user replacement performed" "User path is $MOCK_HOME/sample" "$(cat "$MOCK_HOME/.kiro/prompts/sample.md")"

# Run uninstall
HOME="$MOCK_HOME" uninstall_kiro_prompts "$MOCK_REPO" >/dev/null
check "prompt removed by uninstall" "false" "$([[ -f "$MOCK_HOME/.kiro/prompts/sample.md" ]] && echo true || echo false)"

# A prompt is installed only when every SKILL.md it names is in the global kiro
# dir: pack skills live only in the repos that list them.
mkdir -p "$MOCK_HOME/.kiro/skills/core"; touch "$MOCK_HOME/.kiro/skills/core/SKILL.md"
echo "Read /Users/<user>/.kiro/skills/core/SKILL.md" > "$MOCK_REPO/agents/kiro/prompts/core.md"
echo "Read /Users/<user>/.kiro/skills/pack/SKILL.md" > "$MOCK_REPO/agents/kiro/prompts/pack.md"
echo "stale copy" > "$MOCK_HOME/.kiro/prompts/pack.md"
out=$(HOME="$MOCK_HOME" install_kiro_prompts "$MOCK_REPO")
check "prompt for a global skill installed" "true" "$([[ -f "$MOCK_HOME/.kiro/prompts/core.md" ]] && echo true || echo false)"
check "prompt naming no skill installed" "true" "$([[ -f "$MOCK_HOME/.kiro/prompts/sample.md" ]] && echo true || echo false)"
check "prompt for a missing skill not installed, old copy removed" "false" "$([[ -e "$MOCK_HOME/.kiro/prompts/pack.md" ]] && echo true || echo false)"
check "skipped prompt named in the output" "true" "$([[ "$out" == *"pack.md"* ]] && echo true || echo false)"
HOME="$MOCK_HOME" uninstall_kiro_prompts "$MOCK_REPO" >/dev/null
rm -f "$MOCK_REPO/agents/kiro/prompts/"{core,pack}.md

# Prompts deleted from the repo are still removed from hosts that installed them.
echo "old" > "$MOCK_HOME/.kiro/prompts/audit.md"
HOME="$MOCK_HOME" install_kiro_prompts "$MOCK_REPO" >/dev/null
check "install removes a retired prompt" "false" "$([[ -e "$MOCK_HOME/.kiro/prompts/audit.md" ]] && echo true || echo false)"
echo "old" > "$MOCK_HOME/.kiro/prompts/plan-story.md"
HOME="$MOCK_HOME" uninstall_kiro_prompts "$MOCK_REPO" >/dev/null
check "uninstall removes a retired prompt" "false" "$([[ -e "$MOCK_HOME/.kiro/prompts/plan-story.md" ]] && echo true || echo false)"

# Real repository installation test into mock HOME, with every skill the prompts name
for skill in $(grep -ohE '\.kiro/skills/[^/]+/SKILL\.md' "$REPO_DIR"/agents/kiro/prompts/*.md | sort -u); do
  mkdir -p "$MOCK_HOME/$(dirname "$skill")"; touch "$MOCK_HOME/$skill"
done
HOME="$MOCK_HOME" install_kiro_prompts "$REPO_DIR" >/dev/null
installed_count=$(find "$MOCK_HOME/.kiro/prompts" -name "*.md" | wc -l | tr -d ' ')
check "all 4 repository kiro prompts installed" "4" "$installed_count"

# Real repository uninstallation test from mock HOME
HOME="$MOCK_HOME" uninstall_kiro_prompts "$REPO_DIR" >/dev/null
remaining_count=$(find "$MOCK_HOME/.kiro/prompts" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
check "all 4 repository kiro prompts uninstalled" "0" "$remaining_count"

if [[ "$fails" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "$fails test(s) failed"
  exit 1
fi
