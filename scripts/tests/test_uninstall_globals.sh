#!/usr/bin/env bash
# Tests for uninstall_npm_skill / uninstall_pip_skill / _other_skills_runtimes.
#
# npm -g and pip are machine-wide: redirecting HOME does not scope them. Both
# skills repos declare @fission-ai/openspec, so uninstalling either repo used to
# run `npm uninstall -g` on the package the OTHER repo's /opsx:* archive step
# needs. The reporters also printed "✓ ... uninstalled" unconditionally, because
# `|| true` swallowed npm's non-zero exit -- a no-op read as a removal.
#
# npm and pip are STUBBED in every case: this test must never touch a real
# global package. HOME is redirected so no real runtime dir is inspected.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_DIR/scripts/_lib.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

fails=0
ok()   { echo "OK: $1"; }
bad()  { echo "FAIL: $1"; fails=$((fails + 1)); }

# run_uninstall <fn> <home> <own-runtime-name> <stub-exit>
#   Stubs npm/pip to record that they ran and exit <stub-exit>.
run_uninstall() {
  local fn="$1" home="$2" own="$3" rc="$4"
  HOME="$home" OWN="$own" STUB_RC="$rc" bash -c '
    source "$1" >/dev/null 2>&1
    skills_runtime_dir() { echo "$HOME/$OWN"; }
    npm()  { echo "STUB-RAN"; return "$STUB_RC"; }
    pip3() { echo "STUB-RAN"; return "$STUB_RC"; }
    pip()  { echo "STUB-RAN"; return "$STUB_RC"; }
    command() {
      # make `command -v pip3` succeed so uninstall_pip_skill reaches the guard
      case "${2:-}" in pip3|pip|npm) return 0 ;; esac
      builtin command "$@"
    }
    "$2" "@fake/pkg"
  ' _ "$LIB" "$fn" 2>&1
}

mk_runtime() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/.skills-repo-id"; }

# --- sole installed repo: the package IS ours, remove it --------------------
H1="$TMP/h1"; mk_runtime "$H1/.mine" mine
for fn in uninstall_npm_skill uninstall_pip_skill; do
  out=$(run_uninstall "$fn" "$H1" ".mine" 0)
  case "$out" in
    *"uninstalled"*) ok "$fn removes the package when no sibling repo exists" ;;
    *) bad "$fn refused to remove as the sole repo (got: $out)" ;;
  esac
done

# --- sibling repo installed: keep it, and do not even call the tool ---------
H2="$TMP/h2"; mk_runtime "$H2/.mine" mine; mk_runtime "$H2/.other" other
for fn in uninstall_npm_skill uninstall_pip_skill; do
  out=$(run_uninstall "$fn" "$H2" ".mine" 0)
  case "$out" in
    *STUB-RAN*) bad "$fn ran the tool despite a sibling repo being installed" ;;
    *"kept: another skills repo is installed"*) ok "$fn keeps a shared global and says why" ;;
    *) bad "$fn neither removed nor explained (got: $out)" ;;
  esac
done

# --- a failed removal must not report success ------------------------------
H3="$TMP/h3"; mk_runtime "$H3/.mine" mine
for fn in uninstall_npm_skill uninstall_pip_skill; do
  out=$(run_uninstall "$fn" "$H3" ".mine" 1)
  case "$out" in
    *"✓"*) bad "$fn claimed success for a removal that failed" ;;
    *) ok "$fn reports a failed removal honestly" ;;
  esac
done

# --- _other_skills_runtimes: . and .. must not count as sibling repos ------
# "$HOME"/.* matches . and .., and $HOME/.. is the parent: a marker anywhere
# above HOME would otherwise read as a sibling and block a valid uninstall.
H4="$TMP/h4"; mk_runtime "$H4/.mine" mine
printf 'above-home\n' > "$TMP/.skills-repo-id"   # marker in HOME's parent
got=$(HOME="$H4" bash -c 'source "$1" >/dev/null 2>&1; _other_skills_runtimes "$HOME/.mine"' _ "$LIB" 2>/dev/null)
[[ -z "$got" ]] && ok "a marker above HOME is not treated as a sibling repo" \
                || bad "glob leaked non-runtime entries: $got"

# --- and it does find a real sibling, one per line -------------------------
H5="$TMP/h5"; mk_runtime "$H5/.mine" mine; mk_runtime "$H5/.a" a; mk_runtime "$H5/.b" b
got=$(HOME="$H5" bash -c 'source "$1" >/dev/null 2>&1; _other_skills_runtimes "$HOME/.mine"' _ "$LIB" 2>/dev/null | sort | tr '\n' ' ')
[[ "$got" == "$H5/.a $H5/.b " ]] && ok "lists every other runtime dir, excluding our own" \
                                 || bad "unexpected sibling list: $got"

# A plain dotdir without a marker is not a runtime dir.
H6="$TMP/h6"; mk_runtime "$H6/.mine" mine; mkdir -p "$H6/.config"
got=$(HOME="$H6" bash -c 'source "$1" >/dev/null 2>&1; _other_skills_runtimes "$HOME/.mine"' _ "$LIB" 2>/dev/null)
[[ -z "$got" ]] && ok "a dotdir with no marker is not a runtime dir" \
                || bad "counted a non-runtime dotdir: $got"

[[ $fails -eq 0 ]] || { echo "$fails test(s) failed"; exit 1; }
echo "All uninstall-globals tests passed."
