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
printf '{"features": [{"id":"feat-001","status": "completed"}]}\n' > "$d/feature_list.json"
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
grep -q 'weekly-review:plan' "$report" && ok "leaves plan marker" || bad "plan marker" "missing"

set +e; WEEKLY_REVIEW_REPO_DIR="$d" bash "$SCRIPT" --days abc >/dev/null 2>&1; s=$?; set -e
[[ $s -eq 2 ]] && ok "rejects non-integer --days" || bad "rejects non-integer --days" "exit $s"

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
