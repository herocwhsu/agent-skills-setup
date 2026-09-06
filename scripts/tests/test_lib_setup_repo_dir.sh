#!/usr/bin/env bash
# Tests for setup_repo_dir / _skills_repo_id in lib/lib.sh.
#
# lib.sh is *copied* into the runtime dir by install_runtime_dir, so it cannot
# resolve the repo from its own location. It finds the tree through an installed
# skill symlink and picks the right one by matching .skills-repo-id.
#
# Each case builds its own runtime dir (a copy of lib.sh plus a marker) and its
# own HOME. That is the production seam: sourcing the in-tree lib/lib.sh instead
# would inherit this repo's real marker and silently test only one identity.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_DIR/lib/lib.sh"
[[ -f "$LIB" ]] || { echo "FAIL: lib.sh not found at $LIB"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)   # macOS mktemp yields /var -> /private/var

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

# make_repo <dir> <id|->   fake working tree; "-" writes no marker
make_repo() {
  local d="$1" id="$2"
  mkdir -p "$d/skills/apidog" "$d/scripts"
  : > "$d/registry.txt"
  [[ "$id" == "-" ]] || printf '%s\n' "$id" > "$d/.skills-repo-id"
}

# make_runtime <dir> <id|->   installed runtime dir; "-" simulates a pre-marker install
make_runtime() {
  local d="$1" id="$2"
  mkdir -p "$d"
  cp "$LIB" "$d/lib.sh"
  [[ "$id" == "-" ]] || printf '%s\n' "$id" > "$d/.skills-repo-id"
}

# resolve <runtime-dir> <home>
resolve() {
  HOME="$2" bash -c 'source "$0" >/dev/null 2>&1; setup_repo_dir' "$1/lib.sh" 2>/dev/null || true
}
resolve_err() {
  HOME="$2" bash -c 'source "$0" >/dev/null 2>&1; setup_repo_dir' "$1/lib.sh" 2>&1 >/dev/null || true
}

# --- the collision this exists to prevent -----------------------------------
# Two forks, same shape, both installed. Before identity matching, whichever the
# glob reached first won and a skill could be handed the wrong sibling's scripts/.
A="$TMP/agent-skills-setup"; make_repo "$A" agent-skills-setup
B="$TMP/we-skills";          make_repo "$B" we-skills
RT_A="$TMP/rt-a"; make_runtime "$RT_A" agent-skills-setup
RT_B="$TMP/rt-b"; make_runtime "$RT_B" we-skills

H="$TMP/home-both"; mkdir -p "$H/.claude/skills"
ln -sfn "$A/skills/apidog" "$H/.claude/skills/apidog"
ln -sfn "$B/skills/apidog" "$H/.claude/skills/we-apidog"

check "picks its own tree when a sibling fork is installed"    "$A" "$(resolve "$RT_A" "$H")"
check "sibling runtime picks the sibling tree, same HOME"      "$B" "$(resolve "$RT_B" "$H")"

# Reversed symlink creation order: proves ordering is not what selects the tree.
H2="$TMP/home-both-rev"; mkdir -p "$H2/.claude/skills"
ln -sfn "$B/skills/apidog" "$H2/.claude/skills/aaa-we"
ln -sfn "$A/skills/apidog" "$H2/.claude/skills/zzz-ass"
check "selection is by identity, not glob order"               "$A" "$(resolve "$RT_A" "$H2")"

# --- basic resolution across agent dirs -------------------------------------
H3="$TMP/home-kiro"; mkdir -p "$H3/.kiro/skills"
ln -sfn "$A/skills/apidog" "$H3/.kiro/skills/apidog"
check "resolves via ~/.kiro/skills too"                        "$A" "$(resolve "$RT_A" "$H3")"

# --- an id that matches nothing installed -----------------------------------
RT_C="$TMP/rt-c"; make_runtime "$RT_C" other-skills
check "unmatched id resolves to nothing"                       ""   "$(resolve "$RT_C" "$H")"
case "$(resolve_err "$RT_C" "$H")" in
  *"identifying as 'other-skills'"*) echo "OK: error names the id it wanted" ;;
  *) echo "FAIL: error does not name the wanted id"; fails=$((fails + 1)) ;;
esac

# --- pre-marker install keeps working ---------------------------------------
# An existing host that has not re-run install.sh has no marker beside lib.sh.
# It must still resolve, by the old shape check, and say that it did so.
RT_OLD="$TMP/rt-old"; make_runtime "$RT_OLD" -
H4="$TMP/home-old"; mkdir -p "$H4/.claude/skills"
ln -sfn "$A/skills/apidog" "$H4/.claude/skills/apidog"
check "pre-marker runtime still resolves (shape fallback)"     "$A" "$(resolve "$RT_OLD" "$H4")"

# A tree with neither marker nor registry.txt is still rejected under fallback.
BARE="$TMP/bare"; mkdir -p "$BARE/skills/apidog" "$BARE/scripts"
H5="$TMP/home-bare"; mkdir -p "$H5/.claude/skills"
ln -sfn "$BARE/skills/apidog" "$H5/.claude/skills/apidog"
check "fallback still requires registry.txt"                   ""   "$(resolve "$RT_OLD" "$H5")"

# --- nothing installed at all ----------------------------------------------
H6="$TMP/home-empty"; mkdir -p "$H6"
check "no symlinks resolves to nothing"                        ""   "$(resolve "$RT_A" "$H6")"
case "$(resolve_err "$RT_A" "$H6")" in
  *install.sh*) echo "OK: error tells the user how to fix it" ;;
  *) echo "FAIL: error lacks a remedy"; fails=$((fails + 1)) ;;
esac

# --- marker hygiene --------------------------------------------------------
RT_WS="$TMP/rt-ws"; mkdir -p "$RT_WS"; cp "$LIB" "$RT_WS/lib.sh"
printf '  agent-skills-setup  \n\n' > "$RT_WS/.skills-repo-id"
check "surrounding whitespace in the marker is ignored"        "$A" "$(resolve "$RT_WS" "$H")"

# --- install_runtime_dir: marker handling, exercised not grepped ------------
# This was a grep for the cp line, which passed whether or not the cp was guarded
# -- and an unguarded cp took all of install.sh down at line 62 for any tree
# without a marker. HOME is redirected: install_runtime_dir writes to
# $HOME/.agent-skills-setup and would otherwise overwrite the real one.

# fake_src <dir> <id|->   a tree install_runtime_dir can be pointed at
fake_src() {
  local d="$1" id="$2"
  mkdir -p "$d/lib" "$d/scripts/credentials"
  cp "$LIB" "$d/lib/lib.sh"
  : > "$d/scripts/credentials/_store.sh"
  [[ "$id" == "-" ]] || printf '%s\n' "$id" > "$d/.skills-repo-id"
}

# run_install_runtime <src> <home>  -> "exit|stderr"
run_install_runtime() {
  local out rc
  out=$(HOME="$2" bash -c '
    set -euo pipefail
    source "$0" >/dev/null 2>&1
    install_runtime_dir "$1" >/dev/null
  ' "$REPO_DIR/scripts/_lib.sh" "$1" 2>&1) && rc=0 || rc=$?
  printf '%s|%s' "$rc" "$out"
}

SRC_ID="$TMP/src-id"; fake_src "$SRC_ID" agent-skills-setup
H_ID="$TMP/home-rt-id"; mkdir -p "$H_ID"
res=$(run_install_runtime "$SRC_ID" "$H_ID")
check "marker present: install_runtime_dir exits 0"  "0" "${res%%|*}"
check "marker reaches the runtime dir"               "agent-skills-setup" \
      "$(head -1 "$H_ID/.agent-skills-setup/.skills-repo-id" 2>/dev/null | tr -d '[:space:]')"

# A tree with no marker is a supported state (setup_repo_dir has a shape
# fallback), so this must warn and carry on -- not abort the install.
SRC_NO="$TMP/src-nomarker"; fake_src "$SRC_NO" -
H_NO="$TMP/home-rt-nomarker"; mkdir -p "$H_NO"
res=$(run_install_runtime "$SRC_NO" "$H_NO")
check "no marker: install_runtime_dir still exits 0" "0" "${res%%|*}"
case "${res#*|}" in
  *"no .skills-repo-id"*) echo "OK: absent marker warns on stderr" ;;
  *) echo "FAIL: absent marker warned nothing (got: ${res#*|})"; fails=$((fails + 1)) ;;
esac
[[ -e "$H_NO/.agent-skills-setup/.skills-repo-id" ]] \
  && { echo "FAIL: wrote a marker that the source tree does not have"; fails=$((fails + 1)); } \
  || echo "OK: no marker written when the tree has none"

# Re-installing from a tree that dropped its marker must clear the stale one,
# or the runtime keeps claiming an identity its tree no longer has.
res=$(run_install_runtime "$SRC_NO" "$H_ID")
check "re-install from an unmarked tree exits 0"     "0" "${res%%|*}"
[[ -e "$H_ID/.agent-skills-setup/.skills-repo-id" ]] \
  && { echo "FAIL: stale marker survived a re-install"; fails=$((fails + 1)); } \
  || echo "OK: stale marker cleared on re-install"

# --- the shape fallback must say so ---------------------------------------
# A silent fallback is indistinguishable from a real identity match.
case "$(resolve_err "$RT_OLD" "$H4")" in
  *"selecting the skills tree by"*) echo "OK: shape fallback announces itself" ;;
  *) echo "FAIL: shape fallback is silent"; fails=$((fails + 1)) ;;
esac

# --- this repo ships its own marker ---------------------------------------
if [[ -f "$REPO_DIR/.skills-repo-id" ]]; then
  id=$(head -1 "$REPO_DIR/.skills-repo-id" | tr -d '[:space:]')
  check "repo marker says agent-skills-setup"                  "agent-skills-setup" "$id"
else
  echo "FAIL: repo has no .skills-repo-id"; fails=$((fails + 1))
fi

# --- regression: the recipe that shipped a bare $REPO_DIR -----------------
grep -q 'REPO_DIR=$(setup_repo_dir)' "$REPO_DIR/skills/apidog/diff/IMPL.md" \
  && echo "OK: apidog/diff defines REPO_DIR before using it" \
  || { echo "FAIL: apidog/diff uses \$REPO_DIR without defining it"; fails=$((fails + 1)); }

[[ $fails -eq 0 ]] || { echo "$fails test(s) failed"; exit 1; }
echo "All setup_repo_dir tests passed."
