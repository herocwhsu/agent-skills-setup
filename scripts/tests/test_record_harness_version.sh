#!/usr/bin/env bash
# Tests for record_harness_version in scripts/_lib.sh: the file a target repo's
# preflight compares against, so it must name the commit that was really installed.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

fails=0
check() {
  if [[ "$2" == "$3" ]]; then echo "OK: $1"; else echo "FAIL: $1"; echo "      expected: $2"; echo "      actual:   $3"; fails=$((fails + 1)); fi
}
field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print("null" if v is None else str(v).lower() if isinstance(v,bool) else v)' "$1" "$2"; }

run() { # <repo> -> runs record_harness_version with HOME=$TMP/home, prints output
  ( export HOME="$TMP/home"; mkdir -p "$HOME"
    # shellcheck source=scripts/_lib.sh
    source "$REPO_DIR/scripts/_lib.sh"
    record_harness_version "$1" ) 2>&1
}
OUT="$TMP/home/.agent-skills-setup/harness-version.json"

R="$TMP/repo with \"quotes\""; mkdir -p "$R"; git -C "$R" init -q
printf 'a\n' > "$R/f"; git -C "$R" add f; git -C "$R" -c user.email=t@example.com -c user.name=t commit -qm one
run "$R" >/dev/null
check "commit is HEAD" "$(git -C "$R" rev-parse HEAD)" "$(field "$OUT" commit)"
check "short commit" "$(git -C "$R" rev-parse --short HEAD)" "$(field "$OUT" short)"
check "clean tree is not dirty" "false" "$(field "$OUT" dirty)"
check "installed_at is set" "yes" "$( [[ -n "$(field "$OUT" installed_at)" && "$(field "$OUT" installed_at)" != null ]] && echo yes)"

git -C "$R" tag v1.2.0
run "$R" >/dev/null
check "describe uses the tag" "v1.2.0" "$(field "$OUT" describe)"

printf 'b\n' >> "$R/f"
run "$R" >/dev/null
check "uncommitted tracked change is dirty" "true" "$(field "$OUT" dirty)"

N="$TMP/not-git"; mkdir -p "$N"
msg=$(run "$N")
check "outside git: commit null" "null" "$(field "$OUT" commit)"
check "outside git: reason given" "not a git checkout" "$(field "$OUT" reason)"
check "outside git: warns" "yes" "$( [[ "$msg" == *WARN* ]] && echo yes)"

[[ $fails -eq 0 ]] && echo "test_record_harness_version: all passed" || { echo "test_record_harness_version: $fails failed"; exit 1; }
