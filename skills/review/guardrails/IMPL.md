---
subcommand: guardrails
group: review
slash: /review-guardrails <STORY-ID> <pr-number>
output: stdout only
---

# review/guardrails — Implementation Guardrail Checker

Compares what a PR implements against the approved OpenSpec proposal.
Surfaces missing requirements, extra behavior, and risky changes.

Merged: implementation-guardrail-checker + pr-spec-compliance-checker
(both compare implementation against approved spec — same trigger, same input).

Corresponds to workflow spec §14.10, skills 31 and 32.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
STORY_DIR=$(resolve_story_dir "$1") || exit 1
PR_NUMBER="$2"
```

Requires `gh` CLI authenticated. OpenSpec proposal must exist:
```
./openspec/changes/<change-id>/proposal.md
./openspec/changes/<change-id>/tasks.md
```

## Step 1 — Read approved spec

Read `./openspec/changes/<change-id>/proposal.md`. Extract:
- Goals (what must be implemented)
- Non-goals (what must NOT be implemented)
- Acceptance criteria

Read `./openspec/changes/<change-id>/tasks.md` for the task list.

## Step 2 — Fetch PR diff

```bash
gh pr diff "$PR_NUMBER" > /tmp/_pr_diff.txt
gh pr view "$PR_NUMBER" --json title,body,files > /tmp/_pr_meta.json
```

## Step 3 — Check for compliance issues

| Category | Check |
|---|---|
| Missing requirements | Goals in the proposal that have no corresponding code change |
| Extra behavior | Code changes that implement something not in the proposal or tasks |
| Non-goal violations | Code that implements something explicitly listed as a non-goal |
| API contract drift | API changes that don't match `apidog/contract.md` |
| Permission gaps | Actions that lack a permission check (compare against domain-risk.md) |
| Missing migration | DB schema changes without a migration file |
| Missing tests | Changed behavior with no corresponding test change |

## Output

Print to stdout (optionally append to PR comment draft):

```
Guardrails Check: <STORY-ID> — PR #<number>
============================================================

OpenSpec change: <change-id>
PR: <title>

IMPLEMENTED requirements:
  ✓ Camera group filter added to events query
  ✓ Permission check for cameraGroupId added
  ✓ Pagination preserved

MISSING requirements (in spec, not in PR):
  ✗ Rate limiting not implemented (required per proposal §API Design)
  ✗ Audit log entry missing (required per domain-risk.md)

EXTRA behavior (in PR, not in spec):
  ⚠ Added cameraType filter — not in proposal. Confirm with PM if intentional.
    If intentional: run /review-amend or /review-change-request

NON-GOAL violations:
  (none)

RISKY changes:
  ⚠ Modified permission middleware in camera_handler.go — review carefully

Test coverage gaps:
  ✗ 403 case for cameraGroupId permission not tested

============================================================
Verdict: FAIL — 3 missing requirements, 1 extra behavior, 1 test gap
```

Print `Verdict: PASS` only when all requirements are implemented, no non-goal
violations, and no missing tests.
