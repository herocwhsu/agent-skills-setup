#!/usr/bin/env bash
# Tests for HUM-18 subagent fan-out refactor.
# Static checks: refactored IMPL.md files must still document the schemas,
# scenarios, and constraints the rest of the workflow depends on.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PR_IMPL="$REPO/skills/review/pr/IMPL.md"
SPEC_IMPL="$REPO/skills/audit/spec/IMPL.md"
PROMPT="$REPO/skills/review/pr/review-prompt.md"

[[ -f "$PR_IMPL" ]]   || { echo "FAIL: $PR_IMPL not found"; exit 1; }
[[ -f "$SPEC_IMPL" ]] || { echo "FAIL: $SPEC_IMPL not found"; exit 1; }
[[ -f "$PROMPT" ]]    || { echo "FAIL: $PROMPT not found"; exit 1; }

pass=0
fail=0
ok()   { echo "  PASS  $1"; pass=$((pass + 1)); }
ng()   { echo "  FAIL  $1"; fail=$((fail + 1)); }
have() { grep -q "$1" "$2" && ok "$3" || ng "$3 (missing in $2: $1)"; }

# --- review/pr Step 7 fan-out ---

have "subagent fan-out" "$PR_IMPL" "review/pr Step 7 mentions fan-out"
have "code-review"      "$PR_IMPL" "review/pr names code-review subagent"
have "spec-guardrails"  "$PR_IMPL" "review/pr names spec-guardrails subagent"
have "security-scan"    "$PR_IMPL" "review/pr names security-scan subagent"
have "single message"   "$PR_IMPL" "review/pr requires concurrent dispatch"
have "claude-sonnet-4-6" "$PR_IMPL" "review/pr keeps default model"
have "REVIEW_PR_MODEL"  "$PR_IMPL" "review/pr keeps model env override"
have '"severity"'       "$PR_IMPL" "review/pr documents finding JSON shape"
have '"playbook_match"' "$PR_IMPL" "review/pr documents playbook_match key"
have "Deduplicate"      "$PR_IMPL" "review/pr documents merge dedupe rule"
have "Cap the comment-draft to 5" "$PR_IMPL" "review/pr keeps 5-issue cap"

# Two-artifact output schema must still be referenced for Step 8 to keep working
have "comment draft"    "$PR_IMPL" "review/pr keeps comment-draft artifact"
have "full report"      "$PR_IMPL" "review/pr keeps full-report artifact"

# Pre-checks must still flow into the merge so blocking signals don't get lost
have "MISSING_TITLE_PREFIX" "$PR_IMPL" "review/pr merges title-prefix pre-check"
have "STALE_COMMENTS"       "$PR_IMPL" "review/pr merges stale-comment pre-check"

# --- audit/spec parallel sections ---

have "5 parallel subagents" "$SPEC_IMPL" "audit/spec dispatches 5 subagents"
have "Section 1"            "$SPEC_IMPL" "audit/spec keeps Section 1 (Actors)"
have "Section 5"            "$SPEC_IMPL" "audit/spec keeps Section 5 (Conflicts)"
have "section_id"           "$SPEC_IMPL" "audit/spec subagent JSON shape documented"
have "must-resolve"         "$SPEC_IMPL" "audit/spec keeps must-resolve class"
have "can-assume"           "$SPEC_IMPL" "audit/spec keeps can-assume class"
have "future-scope"         "$SPEC_IMPL" "audit/spec keeps future-scope class"
have "single message"       "$SPEC_IMPL" "audit/spec requires concurrent dispatch"

# Output schema unchanged so audit-handoff still works
have "audit-report.md"      "$SPEC_IMPL" "audit/spec keeps report path"
have "status: pass"         "$SPEC_IMPL" "audit/spec keeps status frontmatter contract"

# --- review-prompt.md schema unchanged so consumers don't break ---

have "Comment draft format" "$PROMPT" "review-prompt keeps comment-draft format"
have "Full report format"   "$PROMPT" "review-prompt keeps full-report format"

echo
echo "result: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
