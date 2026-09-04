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

# --- install copies the marker into the runtime dir ------------------------
# Without this the marker never reaches an installed host and every install
# silently degrades to the shape fallback.
grep -q 'cp -f "$repo_dir/.skills-repo-id" "$rtdir/.skills-repo-id"' "$REPO_DIR/scripts/_lib.sh" \
  && echo "OK: install_runtime_dir copies .skills-repo-id" \
  || { echo "FAIL: install_runtime_dir does not copy the marker"; fails=$((fails + 1)); }

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
