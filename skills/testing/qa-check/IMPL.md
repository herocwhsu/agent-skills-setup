---
subcommand: qa-check
group: testing
slash: /testing-qa-check <STORY-ID>
output: stdout only
---

# testing/qa-check — QA Coverage Checker

Verifies test coverage before closing the verification gate. Checks that
every acceptance criterion, API error response, and permission rule has a
corresponding test.

Corresponds to workflow spec §14.8, skill 26.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

Reads:
- `$STORY_DIR/test-plan.md`
- `./openspec/changes/<change-id>/specs/` (acceptance scenarios)
- `$STORY_DIR/apidog/contract.md` (error responses)

## Checks to perform

For each acceptance criterion in the OpenSpec specs folder:
- [ ] Is there a unit or integration test that verifies this criterion?

For each API error response in `apidog/contract.md`:
- [ ] Is there a negative test case covering this status code?

For each permission rule in the contract (403 responses):
- [ ] Is there a permission test case (valid token + wrong scope)?

For each known edge case in `audit-report.md`:
- [ ] Is there a test covering it?

## Output

Print to stdout:

```
QA Coverage Check: <JIRA-ID>
============================================================

Acceptance Criteria Coverage:
  ✓ AC-1: User with permission can list events
  ✓ AC-2: User without permission receives 403
  ✗ AC-3: Empty result returns empty array with 200 — NO TEST FOUND

API Error Coverage:
  ✓ 400 — invalid input tested
  ✗ 429 — rate limit not tested
  ✓ 403 — permission denied tested

Permission Coverage:
  ✓ camera:read scope verified
  ✗ Cross-tenant isolation not tested

Summary:
  Criteria covered:  2/3 (67%)
  API errors covered: 2/3 (67%)
  Permission rules:   1/2 (50%)

Gaps (must fix before verification):
  - AC-3: Add test for empty result response
  - 429: Add rate limit test case
  - Cross-tenant: Add tenant isolation test

============================================================
Status: FAIL — 3 gaps remain
```

Print `Status: PASS` only when all criteria, API errors, and permission rules
have corresponding tests.
