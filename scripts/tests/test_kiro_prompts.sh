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

# Real repository installation test into mock HOME
HOME="$MOCK_HOME" install_kiro_prompts "$REPO_DIR" >/dev/null
installed_count=$(find "$MOCK_HOME/.kiro/prompts" -name "*.md" | wc -l | tr -d ' ')
check "all 15 repository kiro prompts installed" "15" "$installed_count"

# Real repository uninstallation test from mock HOME
HOME="$MOCK_HOME" uninstall_kiro_prompts "$REPO_DIR" >/dev/null
remaining_count=$(find "$MOCK_HOME/.kiro/prompts" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
check "all 15 repository kiro prompts uninstalled" "0" "$remaining_count"

if [[ "$fails" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "$fails test(s) failed"
  exit 1
fi
