#!/usr/bin/env bash
# Tests for scripts/get-changed-files.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/get-changed-files.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

repo="$TMPDIR/repo"
mkdir -p "$repo"
(
  cd "$repo"
  git init -q
  git config user.email t@t; git config user.name t
  echo "*.ignored" > .gitignore
  echo "initial" > tracked.txt
  git add .gitignore tracked.txt
  git commit -m "init" -q
)

run_detector() {
  GET_CHANGED_REPO_DIR="$repo" bash "$SCRIPT" "$@"
}

# 1. Clean repo -> empty output
out=$(run_detector)
[[ -z "$out" ]] && ok "clean repo emits empty output" || bad "clean repo emits empty output" "got: $out"

# 2. Modified tracked file
echo "change" >> "$repo/tracked.txt"
out=$(run_detector)
[[ "$out" == "tracked.txt" ]] && ok "detects modified tracked file" || bad "detects modified tracked file" "got: $out"

# 3. Staged file
( cd "$repo" && git add tracked.txt )
out=$(run_detector)
[[ "$out" == "tracked.txt" ]] && ok "detects staged file" || bad "detects staged file" "got: $out"

# 4. Untracked file
echo "new" > "$repo/untracked.txt"
out=$(run_detector)
grep -q "tracked.txt" <<<"$out" && grep -q "untracked.txt" <<<"$out" \
  && ok "detects untracked file alongside staged file" \
  || bad "detects untracked file" "got: $out"

# 5. Git-ignored file is skipped
echo "secret" > "$repo/test.ignored"
out=$(run_detector)
! grep -q "test.ignored" <<<"$out" \
  && ok "skips git-ignored files" \
  || bad "skips git-ignored files" "ignored file was reported in: $out"

# 6. Compare with base ref
( cd "$repo" && git commit -m "second" -q )
# Now working tree has only untracked.txt and test.ignored
out=$(run_detector HEAD~1)
grep -q "tracked.txt" <<<"$out" && grep -q "untracked.txt" <<<"$out" \
  && ok "compares correctly against base ref HEAD~1" \
  || bad "compares with base ref" "got: $out"

echo ""
echo "test_changed_files_detector: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
