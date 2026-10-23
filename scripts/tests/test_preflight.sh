#!/usr/bin/env bash
# test_preflight.sh — common/preflight.sh: a short session-start brief that never
# blocks, with harness checks only where the harness is installed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRE="$(cd "$SCRIPT_DIR/../templates/hooks/common" && pwd)/preflight.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }
has()  { if [[ "$OUT" == *"$2"* ]]; then ok "$1"; else bad "$1" "missing '$2' in: $OUT"; fi; }
hasnt() { if [[ "$OUT" != *"$2"* ]]; then ok "$1"; else bad "$1" "unexpected '$2' in: $OUT"; fi; }

R="$TMP/repo"; mkdir -p "$R"; git -C "$R" init -q
long=$(printf 'x%.0s' $(seq 1 300))
{
  echo "# Progress"; echo; echo "## Current state"; echo
  echo "- All green since 10-14."; echo "  - nested detail that must not show"
  echo "Prose state line one,"; echo "continued on line two."
  echo; echo "## In flight"; echo
  echo "- wrapped item starts here"; echo "  and ends on the next line."
  for i in 1 2 3 4 5 6 7 8 9 10; do echo "- item $i"; done
  echo "- $long"
  echo; echo "## Done 2026-10-14"; echo; echo "- old done work that must not show"
  echo; echo "## Next"; echo; echo "1. **First** next step"; echo "2. second"
} > "$R/PROGRESS.md"
run() { OUT=$( cd "$R" && HOME="${2:-$TMP/nohome}" bash "$PRE" < /dev/null 2>&1 ); RC=$?; }

run
if [[ $RC -eq 0 ]]; then ok "exits 0"; else bad "exits 0" "rc=$RC"; fi
has "shows current state" "All green since 10-14."
hasnt "skips nested lines" "nested detail"
has "shows in-flight items" "- item 1"
has "shows a prose paragraph joined" "Prose state line one, continued on line two."
has "joins a wrapped item" "- wrapped item starts here and ends on the next line."
hasnt "caps in-flight at 8" "- item 8"
hasnt "skips Done sections" "old done work"
has "shows next items" "1. **First** next step"
has "names a missing section" "Standing decisions: (none)"
if [[ "$(printf '%s\n' "$OUT" | awk '{ if (length($0) > m) m = length($0) } END { print m }')" -le 170 ]]; then
  ok "clips long items"; else bad "clips long items" "a line is over 170 chars"; fi
has "says when the repo has no agent-harness.json" "no agent-harness.json in this repo"

rm "$R/PROGRESS.md"; run
if [[ $RC -eq 0 && "$OUT" == *"no PROGRESS.md"* ]]; then ok "missing PROGRESS.md: says so, exits 0"; else bad "missing PROGRESS.md" "rc=$RC out=$OUT"; fi

# With an installed harness whose adapter reports drift and a missing state file.
H="$TMP/home"; HS="$TMP/harness"; mkdir -p "$H/.agent-skills-setup" "$HS/scripts" "$HS/templates/hooks/common" "$R/.claude/hooks"
cp "$SCRIPT_DIR/harness_adapter.py" "$SCRIPT_DIR/repo_audit.py" "$HS/scripts/"
printf 'echo a\n' > "$HS/templates/hooks/common/x.sh"; printf 'echo changed\n' > "$R/.claude/hooks/x.sh"
printf '{"schema_version":1,"harness":{"source":"agent-skills-setup","version":"old1234"},"project":{"name":"r"},"state_files":["PROGRESS.md"],"verify":["true"],"hooks":[{"template":"common/x.sh","event":"edit"}]}\n' > "$R/agent-harness.json"
printf '{"commit":"new5678ff","short":"new5678","source_dir":"%s"}\n' "$HS" > "$H/.agent-skills-setup/harness-version.json"
run
has "says when the harness is not installed" "harness not installed on this host"
run "" "$H"
if [[ $RC -eq 0 ]]; then ok "exits 0 with problems found"; else bad "exits 0 with problems found" "rc=$RC"; fi
has "reports version drift" "last changed by old1234, installed new5678"
has "reports hook drift" ".claude/hooks/x.sh differs"
has "reports a missing state file" "PROGRESS.md"

# Started above registered repos: their hooks do not load, so say which repos.
P="$TMP/parent"; mkdir -p "$P/hangar" "$P/atelier" "$P/other"
git -C "$P/hangar" init -q; git -C "$P/atelier" init -q
HR="$TMP/regHome"; mkdir -p "$HR/.agent-skills-setup"
printf '%s\n%s\n' "$P/hangar" "$P/atelier" > "$HR/.agent-skills-setup/target-repos.txt"
runin() { OUT=$( cd "$1" && HOME="$2" bash "$PRE" < /dev/null 2>&1 ); RC=$?; }
runin "$P" "$HR"
if [[ $RC -eq 0 ]]; then ok "above repos: exits 0"; else bad "above repos: exits 0" "rc=$RC"; fi
has "above repos: warns that hooks do not load" "WARN started above registered repos"
has "above repos: names the first repo" "$P/hangar"
has "above repos: names the second repo" "$P/atelier"
runin "$P/hangar" "$HR"
hasnt "inside a registered repo: no extra warning" "started above"
runin "$P/other" "$HR"
hasnt "non-repo folder with no registered repo below: no warning" "started above"
runin "$P" "$TMP/nohome"
hasnt "no registry: no warning" "started above"

echo ""
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
