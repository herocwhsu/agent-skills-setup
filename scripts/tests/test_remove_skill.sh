#!/usr/bin/env bash
# Tests for remove_skill in scripts/_lib.sh.
#
# ~/.claude/skills is one flat namespace shared by every installed repo, and two
# repos built from this one ship the same skill names. remove_skill's comment
# claimed it "only removes if it's a symlink pointing into this repo" while the
# code tested `-L || -d` and never read the target, so one repo's uninstall
# deleted the other's live links. Provenance is now checked; these cases pin it.
#
# HOME is redirected per case: remove_skill writes under $HOME/.claude/skills.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_DIR/scripts/_lib.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

fails=0
check() {
  local label="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then
    echo "OK: $label"
  else
    echo "FAIL: $label"
    echo "    want: $want"
    echo "    got:  $got"
    fails=$((fails + 1))
  fi
}

# fake_repo <dir> <id>  a tree whose skills/ can be linked into a target dir
fake_repo() {
  mkdir -p "$1/skills/apidog" "$1/skills/own-only"
  printf '%s\n' "$2" > "$1/.skills-repo-id"
}

MINE="$TMP/mine";  fake_repo "$MINE" mine
THEIRS="$TMP/theirs"; fake_repo "$THEIRS" theirs

H="$TMP/home"; SKILLS="$H/.claude/skills"; mkdir -p "$SKILLS"
ln -sfn "$THEIRS/skills/apidog"   "$SKILLS/apidog"     # the sibling's link
ln -sfn "$MINE/skills/own-only"   "$SKILLS/own-only"   # ours
mkdir -p "$SKILLS/copied-upstream"                     # a `cp -r` install, no provenance

out=$(HOME="$H" REPO_DIR="$MINE" bash -c '
  source "$1" >/dev/null 2>&1
  for n in apidog own-only copied-upstream; do
    remove_skill "$n" "$HOME/.claude/skills"
  done' _ "$LIB" 2>&1)

# The whole point: a link into another tree must survive our uninstall.
check "sibling's symlink survives our uninstall" "$THEIRS/skills/apidog" \
      "$(readlink "$SKILLS/apidog" 2>/dev/null || true)"
case "$out" in
  *"installed from another tree"*) echo "OK: skip is reported, not silent" ;;
  *) echo "FAIL: nothing said about the skipped skill"; fails=$((fails + 1)) ;;
esac

# ...without over-blocking: our own link and a copied dir must still go.
[[ -e "$SKILLS/own-only" ]] \
  && { echo "FAIL: refused to remove our own symlink"; fails=$((fails + 1)); } \
  || echo "OK: our own symlink is removed"
[[ -e "$SKILLS/copied-upstream" ]] \
  && { echo "FAIL: left a copied skill dir behind"; fails=$((fails + 1)); } \
  || echo "OK: a copied directory is removed"

# An explicit repo_dir argument wins over $REPO_DIR.
H2="$TMP/home2"; mkdir -p "$H2/.claude/skills"
ln -sfn "$THEIRS/skills/apidog" "$H2/.claude/skills/apidog"
HOME="$H2" REPO_DIR="$MINE" bash -c '
  source "$1" >/dev/null 2>&1
  remove_skill apidog "$HOME/.claude/skills" "$2"' _ "$LIB" "$THEIRS" >/dev/null 2>&1
[[ -e "$H2/.claude/skills/apidog" ]] \
  && { echo "FAIL: explicit repo_dir did not authorize the removal"; fails=$((fails + 1)); } \
  || echo "OK: explicit repo_dir argument authorizes removal"

# With no repo_dir known at all, stay lenient: a caller that cannot say which
# tree it owns must not be turned into a silent no-op.
H3="$TMP/home3"; mkdir -p "$H3/.claude/skills"
ln -sfn "$THEIRS/skills/apidog" "$H3/.claude/skills/apidog"
HOME="$H3" bash -c '
  unset REPO_DIR
  source "$1" >/dev/null 2>&1
  remove_skill apidog "$HOME/.claude/skills"' _ "$LIB" >/dev/null 2>&1
[[ -e "$H3/.claude/skills/apidog" ]] \
  && { echo "FAIL: lenient fallback became a no-op"; fails=$((fails + 1)); } \
  || echo "OK: no repo_dir known falls back to removing"

# A name that is not installed is a no-op, not an error.
HOME="$H" REPO_DIR="$MINE" bash -c '
  set -euo pipefail
  source "$1" >/dev/null 2>&1
  remove_skill never-installed "$HOME/.claude/skills"' _ "$LIB" >/dev/null 2>&1 \
  && echo "OK: absent skill is a silent no-op" \
  || { echo "FAIL: absent skill returned non-zero"; fails=$((fails + 1)); }

[[ $fails -eq 0 ]] || { echo "$fails test(s) failed"; exit 1; }
echo "All remove_skill tests passed."
