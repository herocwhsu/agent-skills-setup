#!/usr/bin/env bash
# commit-evidence.sh — Stop hook: put the real commit evidence in front of the
# agent instead of asking it to remember to look.
#
# Deliberately NOT named *-guard.sh. The guards (registry/types/tests/secret) are
# validators: they answer pass/fail and are all wired into harness-verify.sh,
# which a ratchet in scripts/tests/test_harness_verify.sh enforces by globbing
# *-guard.sh. This hook is not a validator -- it checks nothing, it surfaces a
# commit range once. Wiring it into harness-verify would be actively harmful:
# that run would consume the state and the real Stop hook would then stay
# silent, and an on-demand verify would exit 1 after every commit.
#
# Part III already says: "After any subagent dispatch, run `git log --oneline
# <base>..HEAD` and `git show --stat <sha>` ... Do not trust verbose subagent
# summaries." That was pure prose, so it held only as long as the agent
# remembered it. This runs the two commands and blocks once, which turns an
# inferential request into a computational check.
#
# On Stop, not SubagentStop: SubagentStop feeds stderr back to the SUBAGENT,
# and the agent that must not trust the summary is the main one. Stop is the
# only timing that reaches it.
#
# Fires at most once per new commit range. The state file records what has
# already been shown, so a second Stop in the same turn exits 0 rather than
# blocking forever.
#
# Exit 2 blocks and feeds stderr back (the only code Claude Code returns to the
# agent); exit 0 allows.
set -uo pipefail

REPO_DIR="${COMMIT_EVIDENCE_REPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO_DIR" 2>/dev/null || exit 0

# Not a git repo, or a repo with no commits yet: nothing to verify.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
head_sha=$(git rev-parse HEAD 2>/dev/null) || exit 0
[[ -n "$head_sha" ]] || exit 0

# State lives inside .git so it can never be committed or scanned as a secret.
state_file="$(git rev-parse --git-dir)/commit-evidence.state"
last=""
[[ -f "$state_file" ]] && last=$(cat "$state_file" 2>/dev/null)

# First ever run: record and stay quiet. Reporting every commit in the repo's
# history on the first Stop would be noise, not evidence.
if [[ -z "$last" ]]; then
  printf '%s\n' "$head_sha" > "$state_file"
  exit 0
fi

# Already reported this HEAD.
[[ "$last" == "$head_sha" ]] && exit 0

# A rebase/reset can leave the recorded sha unreachable; fall back to quiet
# re-baselining rather than emitting a bogus range.
if ! git cat-file -e "$last" 2>/dev/null || ! git merge-base --is-ancestor "$last" "$head_sha" 2>/dev/null; then
  printf '%s\n' "$head_sha" > "$state_file"
  exit 0
fi

range="$last..$head_sha"
shas=$(git rev-list "$range" 2>/dev/null)
if [[ -z "$shas" ]]; then
  printf '%s\n' "$head_sha" > "$state_file"
  exit 0
fi

# Record BEFORE blocking. If this wrote after the exit, the same range would be
# re-reported on the next Stop and the turn could never end.
printf '%s\n' "$head_sha" > "$state_file"

{
  echo "New commits since the last check — verify these against what was claimed,"
  echo "rather than trusting a summary (Part III, Subagent verification):"
  echo
  git log --oneline "$range" 2>&1 | sed 's/^/  /'
  echo
  for s in $shas; do
    git show --stat --format='  %h %an  %s' "$s" 2>&1 | sed 's/^/  /'
    echo
  done
  echo "If this matches the intended change, say so and continue; the check will"
  echo "not fire again for these commits."
} >&2
exit 2
