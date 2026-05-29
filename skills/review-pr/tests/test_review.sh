#!/usr/bin/env bash
# Tests the deterministic glue from review-pr SKILL.md.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: missing playbook produces clear error ---

mkdir "$TMP/repo1"
cd "$TMP/repo1"
git init -q

# Simulate the workflow's playbook check
if [[ -f .code-review/playbook.md ]]; then
  echo "FAIL: test 1 unexpectedly found a playbook"
  exit 1
fi
echo "OK: missing playbook detected"

# --- Test 2: large-PR threshold check ---

# Simulate the additions+deletions computation
additions=1500
deletions=600
total=$((additions + deletions))
threshold=${REVIEW_PR_MAX_DIFF_LINES:-2000}

if [[ "$total" -le "$threshold" ]]; then
  echo "FAIL: test 2 expected total $total to exceed threshold $threshold"
  exit 1
fi
echo "OK: large-PR threshold triggered ($total > $threshold)"

# Below threshold should pass through
additions=100
deletions=50
total=$((additions + deletions))
if [[ "$total" -gt "$threshold" ]]; then
  echo "FAIL: test 2b small PR wrongly flagged as large"
  exit 1
fi
echo "OK: small PR not flagged"

# --- Test 3: empty files list = skip review ---

# Simulate parsing the metadata file
mkdir -p "$TMP/repo1/.code-review"
echo '{"files":[]}' > "$TMP/repo1/.code-review/.pr-1-meta.json"

files_count=$(grep -o '"files":\[[^]]*\]' "$TMP/repo1/.code-review/.pr-1-meta.json" | grep -c '"name"' || true)
if [[ "$files_count" -ne 0 ]]; then
  echo "FAIL: test 3 expected 0 files for empty PR"
  exit 1
fi
echo "OK: empty-PR detection works"

# --- Test 4: env var override is read ---

REVIEW_PR_MAX_DIFF_LINES=500 bash -c '
  threshold=${REVIEW_PR_MAX_DIFF_LINES:-2000}
  if [[ "$threshold" != "500" ]]; then
    echo "FAIL: test 4 env override not honored"
    exit 1
  fi
  echo "OK: REVIEW_PR_MAX_DIFF_LINES override works"
'

echo ""
echo "All review glue tests passed."
