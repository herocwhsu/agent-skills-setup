#!/usr/bin/env bash
# Tests for commit-evidence.sh (Stop hook: surface real commit evidence).
#
# Not named *-guard.sh on purpose -- see the hook's header. The last assertion
# here pins that: it must stay OUT of harness-verify.sh, because a verify run
# would consume the state the real Stop hook needs.
#
# Points the hook at throwaway git repos via COMMIT_EVIDENCE_REPO_DIR. The
# must-not-regress property is that the gate fires ONCE per commit range: a
# gate that keeps blocking would make the turn unable to end, which is worse
# than no gate at all.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/commit-evidence.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

make_repo() {
  local d="$TMPDIR/$1"
  mkdir -p "$d"
  ( cd "$d"
    git init -q
    git config user.email t@t; git config user.name t
    echo one > a.txt
    git add a.txt
    git commit -qm "chore: first" ) >/dev/null 2>&1
  echo "$d"
}
commit_in() { ( cd "$1"; echo "$3" > "$2"; git add "$2"; git commit -qm "feat: add $2" ) >/dev/null 2>&1; }
run_hook() { COMMIT_EVIDENCE_REPO_DIR="$1" bash "$HOOK" 2>&1; }
run_code() { local c=0; COMMIT_EVIDENCE_REPO_DIR="$1" bash "$HOOK" >/dev/null 2>&1 || c=$?; echo "$c"; }

# --- first run baselines quietly: no history dump on a repo it has never seen ---
d=$(make_repo first)
code=$(run_code "$d")
[[ "$code" -eq 0 ]] && ok "first run exits 0 (baseline, no noise)" \
  || bad "first run exits 0" "exit $code"
state="$d/.git/commit-evidence.state"
[[ -f "$state" ]] && ok "state file created inside .git" \
  || bad "state file created inside .git" "missing $state"

# --- no new commits: stays quiet ---
code=$(run_code "$d")
[[ "$code" -eq 0 ]] && ok "unchanged HEAD exits 0" || bad "unchanged HEAD exits 0" "exit $code"

# --- a new commit blocks with exit 2, not 1 ---
commit_in "$d" b.txt two
code=0; out=$(run_hook "$d") || code=$?
if [[ $code -eq 2 ]]; then
  ok "new commit blocks with exit 2"
else
  bad "new commit blocks with exit 2" "got exit $code (1 would not block)"
fi
grep -q 'feat: add b.txt' <<<"$out" \
  && ok "git log output is surfaced" || bad "git log output is surfaced" "out: $out"
grep -qE 'b\.txt \|' <<<"$out" \
  && ok "git show --stat output is surfaced" || bad "git show --stat is surfaced" "out: $out"

# --- THE critical property: it does not block twice for the same commits ---
code=$(run_code "$d")
if [[ "$code" -eq 0 ]]; then
  ok "same commits do not block again (turn can end)"
else
  bad "same commits do not block again" "exit $code — a turn could never complete"
fi

# --- a further commit blocks again (the gate is not one-shot for the repo) ---
commit_in "$d" c.txt three
code=$(run_code "$d")
[[ "$code" -eq 2 ]] && ok "a later commit blocks again" || bad "a later commit blocks again" "exit $code"

# --- only the NEW range is reported, not the whole history ---
commit_in "$d" e.txt five
out=$(run_hook "$d" || true)
if grep -q 'e.txt' <<<"$out" && ! grep -q 'chore: first' <<<"$out"; then
  ok "reports only the new range"
else
  bad "reports only the new range" "leaked older commits: $out"
fi

# --- rewritten history (reset) re-baselines instead of emitting a bogus range ---
d2=$(make_repo rewritten)
run_code "$d2" >/dev/null
commit_in "$d2" b.txt two
run_code "$d2" >/dev/null                       # records the 2nd sha
( cd "$d2"; git reset -q --hard HEAD~1 ) >/dev/null 2>&1   # recorded sha now unreachable
code=$(run_code "$d2")
if [[ "$code" -eq 0 ]]; then
  ok "unreachable recorded sha re-baselines quietly"
else
  bad "unreachable recorded sha re-baselines quietly" "exit $code"
fi

# --- a non-git directory is not an error ---
d3="$TMPDIR/plain"; mkdir -p "$d3"
code=$(run_code "$d3")
[[ "$code" -eq 0 ]] && ok "non-git dir exits 0" || bad "non-git dir exits 0" "exit $code"

# --- a repo with no commits at all is not an error ---
d4="$TMPDIR/empty"; mkdir -p "$d4"
( cd "$d4"; git init -q ) >/dev/null 2>&1
code=$(run_code "$d4")
[[ "$code" -eq 0 ]] && ok "repo with no commits exits 0" || bad "repo with no commits exits 0" "exit $code"

# --- wired into Stop, deliberately NOT SubagentStop ---
# SubagentStop feeds stderr back to the subagent; the agent that must not trust
# the summary is the main one, so Stop is the only timing that reaches it.
SETTINGS="$(cd "$(dirname "$0")/../.." && pwd)/settings.json"
if python3 -c "
import json
d = json.load(open('$SETTINGS'))
stop = [h for e in d['hooks']['Stop'] for h in e['hooks']]
assert any('commit-evidence.sh' in h['command'] for h in stop), 'not in Stop'
sub = [h for e in d['hooks'].get('SubagentStop', []) for h in e['hooks']]
assert not any('commit-evidence.sh' in h['command'] for h in sub), 'must not be in SubagentStop'
" 2>/dev/null; then
  ok "registered in Stop only"
else
  bad "registered in Stop only" "check settings.json wiring"
fi

# --- must NOT be wired into harness-verify.sh ---
HV="$(cd "$(dirname "$0")/../../.." && pwd)/scripts/harness-verify.sh"
if [[ -f "$HV" ]] && grep -q 'commit-evidence' "$HV"; then
  bad "stays out of harness-verify" "wiring it there consumes the state Stop needs"
else
  ok "stays out of harness-verify (not a validator)"
fi

echo ""
echo "test_commit_evidence: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
