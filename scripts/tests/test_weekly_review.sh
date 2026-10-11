#!/usr/bin/env bash
# Tests for scripts/weekly-review.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_DIR/scripts/weekly-review.sh"
[[ -f "$SCRIPT" ]] || { echo "FAIL: script not found at $SCRIPT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

d="$TMP/repo"
mkdir -p "$d/scripts"
cp "$REPO_DIR/scripts/trace-evaluation.sh" "$REPO_DIR/scripts/trace_evaluation.py" "$d/scripts/"
printf '{"features": [{"id":"feat-001","status": "completed","verification":"bash scripts/trace-evaluation.sh && pytest tests/gone.py"}]}\n' > "$d/feature_list.json"
printf '# P\n\n### What'"'"'s Next\n\n1. Do the thing\n\n## Blockers\n' > "$d/PROGRESS.md"
git -C "$d" init -q
git -C "$d" add .
git -C "$d" -c user.name=T -c user.email=t@example.com commit -qm "feat: first change"

out=$(WEEKLY_REVIEW_REPO_DIR="$d" bash "$SCRIPT" 2>&1) && status=0 || status=$?
report="$out"
[[ $status -eq 0 && -f "$report" && "$report" =~ docs/weekly/[0-9]{4}-W[0-9]{2}\.md$ ]] \
  && ok "writes docs/weekly/YYYY-Www.md" || bad "writes report" "exit $status, out: $out"

grep -q 'feat: first change' "$report" && ok "lists commits in window" || bad "lists commits" "missing"
grep -q 'Do the thing' "$report" && ok "includes What's Next queue" || bad "queue" "missing"
grep -q 'Blockers' "$report" && bad "queue stops at next heading" "leaked Blockers" || ok "queue stops at next heading"
grep -q 'completed' "$report" && ok "counts feature status" || bad "feature status" "missing"
grep -q 'feat-001: tests/gone.py' "$report" && ok "flags missing verification path" || bad "missing verification path" "not flagged"
grep -q 'feat-001: scripts/trace-evaluation.sh' "$report" && bad "existing path not flagged" "false positive" || ok "existing path not flagged"
grep -q 'weekly-review:plan' "$report" && ok "leaves plan marker" || bad "plan marker" "missing"

set +e; WEEKLY_REVIEW_REPO_DIR="$d" bash "$SCRIPT" --days abc >/dev/null 2>&1; s=$?; set -e
[[ $s -eq 2 ]] && ok "rejects non-integer --days" || bad "rejects non-integer --days" "exit $s"


# --- edge cases: empty repo, root commit, missing/odd state files -------------
edge() { local n="$1"; local e="$TMP/$n"; mkdir -p "$e/scripts"
  cp "$REPO_DIR/scripts/trace-evaluation.sh" "$REPO_DIR/scripts/trace_evaluation.py" "$e/scripts/"
  git -C "$e" init -q; echo "$e"; }
run_edge() { WEEKLY_REVIEW_REPO_DIR="$1" bash "$SCRIPT" 2>/dev/null; }
commit_all() { git -C "$1" add .; git -C "$1" -c user.name=T -c user.email=t@example.com commit -qm "feat: x"; }

e=$(edge empty)
set +e; out=$(run_edge "$e"); st=$?; set -e
[[ $st -eq 0 ]] && grep -q 'No commits in window' "$out" && ok "empty repo still writes a report" || bad "empty repo" "exit $st: $out"

e=$(edge noprogress); echo '{"features": []}' > "$e/feature_list.json"; commit_all "$e"
set +e; out=$(run_edge "$e"); st=$?; set -e
[[ $st -eq 0 ]] && grep -q 'weekly-review:plan' "$out" && ok "missing PROGRESS.md keeps report complete" || bad "missing PROGRESS.md" "exit $st: $out"

e=$(edge rootcommit); echo '{"features": []}' > "$e/feature_list.json"; echo '# P' > "$e/PROGRESS.md"; commit_all "$e"
set +e; out=$(run_edge "$e"); st=$?; set -e
grep -q 'feature_list.json' <(sed -n '/## Files changed/,/## State/p' "$out") && ok "root commit shows files changed" || bad "root commit" "empty Files changed"

e=$(edge oddverif)
printf '{"features":[{"id":"a","verification":null},{"verification":"bash scripts/tests/test_*.sh; see docs/x.md. then scripts/trace-evaluation.sh"}]}\n' > "$e/feature_list.json"
echo '# P' > "$e/PROGRESS.md"; commit_all "$e"
set +e; out=$(run_edge "$e"); st=$?; set -e
sec=$(sed -n '/## Verification command paths/,/## Queue/p' "$out")
[[ $st -eq 0 ]] && echo "$sec" | grep -q '?: docs/x.md$' && ! echo "$sec" | grep -q 'test_$\|trace-evaluation' \
  && ok "null/odd verification handled, glob skipped, punctuation stripped" || bad "odd verification" "exit $st: $sec"

e=$(edge nofeatures); echo '# P' > "$e/PROGRESS.md"; commit_all "$e"
set +e; out=$(run_edge "$e"); st=$?; set -e
[[ $st -eq 0 ]] && grep -q 'feature_list.json unreadable' "$out" && ok "missing feature_list.json is reported, not fatal" || bad "missing feature_list" "exit $st"

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
