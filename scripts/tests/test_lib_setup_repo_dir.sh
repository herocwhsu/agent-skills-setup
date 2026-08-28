#!/usr/bin/env bash
# Tests for setup_repo_dir in lib/lib.sh.
#
# lib.sh is *copied* to ~/.agent-skills-setup/lib.sh by install_runtime_dir, so it
# cannot resolve the repo from its own location. setup_repo_dir derives it from an
# installed skill symlink instead. These tests fake HOME so the real ~/.claude is
# never read -- otherwise a passing run would only prove this machine is installed.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_DIR/lib/lib.sh"
[[ -f "$LIB" ]] || { echo "FAIL: lib.sh not found at $LIB"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# macOS mktemp returns /var/... which is a symlink to /private/var; setup_repo_dir
# resolves physical paths, so compare against the resolved form.
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

# A plausible working tree: registry.txt is the sentinel, scripts/ the payload dir.
FAKE="$TMP/agent-skills-setup"
mkdir -p "$FAKE/skills/apidog" "$FAKE/scripts"
touch "$FAKE/registry.txt"

# --- Test 1: resolves through an installed skill symlink ---
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/skills"
ln -sfn "$FAKE/skills/apidog" "$HOME/.claude/skills/apidog"
got=$(bash -c 'source "$0" >/dev/null 2>&1; setup_repo_dir' "$LIB" 2>/dev/null || true)
check "resolves via ~/.claude/skills symlink" "$FAKE" "$got"

# --- Test 2: works from a non-Claude agent dir too ---
export HOME="$TMP/home2"
mkdir -p "$HOME/.kiro/skills"
ln -sfn "$FAKE/skills/apidog" "$HOME/.kiro/skills/apidog"
got=$(bash -c 'source "$0" >/dev/null 2>&1; setup_repo_dir' "$LIB" 2>/dev/null || true)
check "resolves via ~/.kiro/skills symlink" "$FAKE" "$got"

# --- Test 3: a symlinked skill collection that is NOT this repo is rejected ---
# Without the registry.txt sentinel any symlinked skills dir would match, and the
# function would hand back a path with no scripts/ in it.
OTHER="$TMP/someone-elses-skills"
mkdir -p "$OTHER/skills/apidog"
export HOME="$TMP/home3"
mkdir -p "$HOME/.claude/skills"
ln -sfn "$OTHER/skills/apidog" "$HOME/.claude/skills/apidog"
if bash -c 'source "$0" >/dev/null 2>&1; setup_repo_dir' "$LIB" >/dev/null 2>&1; then
  echo "FAIL: accepted a tree with no registry.txt"
  fails=$((fails + 1))
else
  echo "OK: rejects a symlinked tree lacking registry.txt"
fi

# --- Test 4: fails loudly, not silently, when nothing is installed ---
export HOME="$TMP/home4"
mkdir -p "$HOME"
if out=$(bash -c 'source "$0" >/dev/null 2>&1; setup_repo_dir' "$LIB" 2>&1); then
  echo "FAIL: returned success with no skills installed (got: $out)"
  fails=$((fails + 1))
else
  case "$out" in
    *"not found"*) echo "OK: fails with a diagnostic when nothing is installed" ;;
    *) echo "FAIL: failed without a usable message (got: $out)"; fails=$((fails + 1)) ;;
  esac
fi

# --- Test 5: regression -- the recipe that shipped a bare $REPO_DIR ---
# skills/apidog/diff/IMPL.md told the agent to run "$REPO_DIR/scripts/..." with
# REPO_DIR undefined at runtime, so the path expanded to /scripts/... and the only
# working read path for a non-default Apidog branch was dead.
IMPL="$REPO_DIR/skills/apidog/diff/IMPL.md"
if grep -q 'REPO_DIR=$(setup_repo_dir)' "$IMPL"; then
  echo "OK: apidog/diff defines REPO_DIR before using it"
else
  echo "FAIL: apidog/diff uses \$REPO_DIR without defining it"
  fails=$((fails + 1))
fi

[[ $fails -eq 0 ]] || { echo "$fails test(s) failed"; exit 1; }
echo "All setup_repo_dir tests passed."
