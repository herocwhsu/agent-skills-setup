#!/usr/bin/env bash
# Tests for install.sh's source guard and saved-selection default.
#
# install.sh symlinks local skills to wherever it runs from, so a run from a
# linked worktree or a feature branch points every agent on the host at
# unmerged skill code, and deleting the worktree later dangles every link.
# Each case installs from a throwaway copy of the repo into a throwaway HOME,
# with network tools stubbed out so the run is offline and fast.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

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

STUBS="$TMP/stubs"
mkdir -p "$STUBS"
for tool in curl wget npm claude pip pip3 codex kiro-cli hermes agy; do
  printf '#!/bin/sh\nexit 1\n' > "$STUBS/$tool"
  chmod +x "$STUBS/$tool"
done

# make_repo <name> — a git repo holding the current working tree, committed on main.
# .mypy_cache is excluded because the types-guard Stop hook runs mypy in parallel
# with this test; copying a cache whose sqlite -wal/-shm files appear and vanish
# makes rsync exit 24 and fails the test at random.
make_repo() {
  local d="$TMP/$1"
  mkdir -p "$d"
  rsync -a --exclude .git --exclude .mypy_cache "$REPO_DIR/" "$d/"
  git -C "$d" init -q -b main
  git -C "$d" -c user.name=t -c user.email=t@t add -A
  git -C "$d" -c user.name=t -c user.email=t@t commit -qm init
  echo "$d"
}

# run_install <repo> <home> [args...] — prints the exit code; output in <home>.out
run_install() {
  local repo="$1" home="$2"; shift 2
  mkdir -p "$home"
  set +e
  HOME="$home" OUTSIDE_AGENT_INIT=0 PATH="$STUBS:$PATH" bash "$repo/scripts/install.sh" "$@" \
    </dev/null >"$home.out" 2>&1
  echo $?
  set -e
}

main_repo=$(make_repo main)

check "installs from main" 0 "$(run_install "$main_repo" "$TMP/h1" --agent claude)"
check "links point into the checkout it ran from" "$main_repo/skills/apidog" \
  "$(readlink "$TMP/h1/.claude/skills/apidog" || true)"
check "install skips outside-agent init when asked" yes \
  "$(grep -q 'skipped (OUTSIDE_AGENT_INIT=0)' "$TMP/h1.out" && echo yes || echo no)"

git -C "$main_repo" checkout -qb feature
check "refuses a feature branch" 1 "$(run_install "$main_repo" "$TMP/h2" --agent claude)"
check "refusal names the branch" yes \
  "$(grep -q "feature" "$TMP/h2.out" && echo yes || echo no)"
check "refusal installs nothing" no \
  "$([[ -e "$TMP/h2/.claude/skills" || -e "$TMP/h2/.agent-skills-setup" ]] && echo yes || echo no)"
check "--allow-non-main overrides the branch check" 0 \
  "$(run_install "$main_repo" "$TMP/h3" --agent claude --allow-non-main)"

git -C "$main_repo" checkout -q --detach main
check "refuses a detached HEAD" 1 "$(run_install "$main_repo" "$TMP/h4" --agent claude)"
git -C "$main_repo" checkout -q main

git -C "$main_repo" worktree add -q --detach "$TMP/wt" main
check "refuses a linked worktree" 1 "$(run_install "$TMP/wt" "$TMP/h5" --agent claude)"
check "refusal names the worktree cause" yes \
  "$(grep -qi "worktree" "$TMP/h5.out" && echo yes || echo no)"

# A release tarball has no .git at all; there is no branch to judge.
plain="$TMP/plain"
mkdir -p "$plain"
rsync -a --exclude .git --exclude .mypy_cache "$REPO_DIR/" "$plain/"
check "installs from a non-git copy" 0 "$(run_install "$plain" "$TMP/h6" --agent claude)"

# --- saved selection is the default when --agent is omitted ---------------
# Before, a bare run fell to the prompt and EOF defaulted to claude, silently
# narrowing a claude,codex host to claude for every later update.sh.
mkdir -p "$TMP/h7/.agent-skills-setup"
echo "claude,codex" > "$TMP/h7/.agent-skills-setup/agent-selection.txt"
check "bare run succeeds with a saved selection" 0 "$(run_install "$main_repo" "$TMP/h7")"
check "bare run keeps the saved selection" "claude,codex" \
  "$(cat "$TMP/h7/.agent-skills-setup/agent-selection.txt")"
check "bare run installs every saved agent" yes \
  "$([[ -L "$TMP/h7/.codex/skills/apidog" ]] && echo yes || echo no)"

if [[ $fails -gt 0 ]]; then
  echo ""
  echo "$fails check(s) failed"
  exit 1
fi
echo ""
echo "all checks passed"
