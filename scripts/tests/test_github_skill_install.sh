#!/usr/bin/env bash
# Tests for install_github_skill in scripts/_lib.sh.
#
# `github` entries are *copied*, not symlinked: the tarball they come from is
# rm -rf'd immediately, so there is nothing stable to link at. That makes the
# copy the whole update path -- re-running install.sh is how these skills move
# to upstream tip -- and it has to REPLACE the installed dir, not merge into it.
#
# download_file is stubbed per case, so nothing here touches the network.
# HOME is redirected because _lib.sh writes to $HOME/.agent-skills-setup.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v zip >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
  echo "SKIP: zip/unzip not available"
  exit 0
fi

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

# make_upstream <dir> — a HEAD.zip whose skills/ holds one skill at "v2"
make_upstream() {
  local d="$1"
  mkdir -p "$d/tree/superpowers-main/skills/brainstorming"
  echo "v2" > "$d/tree/superpowers-main/skills/brainstorming/SKILL.md"
  (cd "$d/tree" && zip -qr "$d/up.zip" .)
}

# run_install <upstream-dir> <target-dir> <home>
#   The stub is passed its inputs through the environment, not positionally:
#   inside download_file, $1/$2 are the function's own args (url, dest) and
#   would shadow anything the outer bash -c was given.
run_install() {
  UPZIP="$1/up.zip" TGT_DIR="$2" REPO="$REPO_DIR" HOME="$3" bash -c '
    set -uo pipefail
    source "$REPO/scripts/_lib.sh" >/dev/null 2>&1
    download_file() { cp "$UPZIP" "$2"; }
    install_github_skill "obra/superpowers" "skills" "$TGT_DIR"
  ' >/dev/null 2>&1 || true
}

# --- the regression: a file deleted upstream must not survive the update ----
# The copy previously merged into the existing dir, so a file upstream had
# removed stayed installed and loadable forever.
UP="$TMP/up1"; make_upstream "$UP"
TGT="$TMP/tgt1"; mkdir -p "$TGT/brainstorming"
echo "v1"    > "$TGT/brainstorming/SKILL.md"
echo "stale" > "$TGT/brainstorming/REMOVED-UPSTREAM.md"
H="$TMP/home1"; mkdir -p "$H"
run_install "$UP" "$TGT" "$H"

check "modified file updates to upstream tip" "v2" "$(cat "$TGT/brainstorming/SKILL.md" 2>/dev/null || true)"
[[ -f "$TGT/brainstorming/REMOVED-UPSTREAM.md" ]] \
  && { echo "FAIL: file deleted upstream survived the update"; fails=$((fails + 1)); } \
  || echo "OK: file deleted upstream is gone after the update"

# Nesting guard: the `*/` glob leaves a trailing slash on the source, and BSD
# and GNU cp disagree about what that means when the destination exists. An
# explicit rm makes the outcome the same on both.
[[ -d "$TGT/brainstorming/brainstorming" ]] \
  && { echo "FAIL: copy nested itself inside the existing dir"; fails=$((fails + 1)); } \
  || echo "OK: no nested skill dir"

# --- a clean install still works -------------------------------------------
UP2="$TMP/up2"; make_upstream "$UP2"
TGT2="$TMP/tgt2"; H2="$TMP/home2"; mkdir -p "$H2"
run_install "$UP2" "$TGT2" "$H2"
check "clean install writes the skill" "v2" "$(cat "$TGT2/brainstorming/SKILL.md" 2>/dev/null || true)"

# --- regression: two installs in a row -------------------------------------
# BSD mktemp ignores a suffix placed after the X's and creates the template
# LITERALLY, unrandomized: `mktemp /tmp/agent-skills-XXXXXX.zip` yielded that
# exact path, so the second call ever made died with "File exists" and every
# later install failed at `unzip: cannot find or open`. One interrupted install
# (before its `rm -f`) poisoned /tmp permanently. GNU mktemp accepts the suffix,
# so CI never saw it -- the same BSD/GNU split AGENTS.md flags for bash 3.2.
UP3="$TMP/up3"; make_upstream "$UP3"
H3="$TMP/home3"; mkdir -p "$H3"
run_install "$UP3" "$TMP/tgt3a" "$H3"
run_install "$UP3" "$TMP/tgt3b" "$H3"
check "a second consecutive install still works" "v2" \
      "$(cat "$TMP/tgt3b/brainstorming/SKILL.md" 2>/dev/null || true)"

# And the literal template must never appear on disk.
for stray in /tmp/agent-skills-XXXXXX /tmp/agent-skills-XXXXXX.zip; do
  [[ -e "$stray" ]] \
    && { echo "FAIL: mktemp created its template literally: $stray"; fails=$((fails + 1)); } \
    || echo "OK: no literal mktemp template at $stray"
done

# Portability guard over shipped code: X's must end the template.
bad=$(grep -rn "mktemp[^|;)]*X\{3,\}[._-][A-Za-z]" --include="*.sh" \
        "$REPO_DIR/scripts" "$REPO_DIR/lib" "$REPO_DIR/hooks" "$REPO_DIR/skills" 2>/dev/null \
        | grep -v "/tests/" || true)
if [[ -n "$bad" ]]; then
  echo "FAIL: mktemp template with a suffix after the X's (breaks on BSD/macOS):"
  echo "$bad" | sed 's/^/    /'
  fails=$((fails + 1))
else
  echo "OK: no mktemp template carries a suffix after the X's"
fi

[[ $fails -eq 0 ]] || { echo "$fails test(s) failed"; exit 1; }
echo "All install_github_skill tests passed."
