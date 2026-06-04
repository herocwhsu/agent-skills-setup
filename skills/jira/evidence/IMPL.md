---
subcommand: evidence
group: jira
slash: /jira-evidence <STORY-ID>
output: stdout only
---

# jira/evidence — Jira Evidence Checker

Verifies that every Jira sub-task on a story has the required evidence links
before closure. Workflow spec §13 hard rule: "No evidence, no closure."

Corresponds to workflow spec §14.6, skill 19.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1

[[ -z "${JIRA_HOST:-}" ]] && { echo "ERROR: JIRA_HOST not in config.sh" >&2; exit 1; }
[[ -z "${JIRA_USER:-}" ]] && { echo "ERROR: JIRA_USER not in config.sh" >&2; exit 1; }
```

## Step 1 — Fetch story sub-tasks

```bash
STORY_ID="$1"
SLUG=$(service_slug jira "https://$JIRA_HOST")
_PASS=$(require_secret "$SLUG" "$JIRA_USER" "bash scripts/credentials/service.sh jira add") || exit 1

curl -s -u "$JIRA_USER:$_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$STORY_ID?fields=subtasks" \
  > /tmp/_story_subtasks.json
unset _PASS
```

For each sub-task, fetch its full details:

```bash
curl -s -u "$JIRA_USER:$_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$SUBTASK_ID?fields=description,status,remoteLinks" \
  > /tmp/_subtask.json
```

## Step 2 — Check required evidence per task type

| Jira item type | Required evidence |
|---|---|
| API design task | Apidog link (or `apidog/contract.md` path) |
| Backend implementation | PR link (GitHub URL) |
| Frontend implementation | PR link or design review link |
| Test task | CI link or test report |
| Spec task | OpenSpec change-id |
| Documentation | Confluence link |
| Verification | QA result or test run link |
| Release | Release note or deployment record |

## Step 3 — Report

Print to stdout:

```
Jira Evidence Check: <STORY-ID>
============================================================

Sub-task evidence:

  <STORY-ID>-1: Implement camera group filter API
  Status: Done
  ✓ PR: https://github.com/org/repo/pull/456
  ✓ CI: https://github.com/org/repo/actions/runs/789
  ✗ Apidog: MISSING — add Apidog contract link

  <STORY-ID>-2: Write integration tests
  Status: In Progress
  ✓ Test report: (pending — task not yet done)

  <STORY-ID>-3: Update Confluence documentation
  Status: Done
  ✗ Confluence: MISSING — link to updated page required

Summary:
  Sub-tasks checked: 3
  Ready to close:    1
  Missing evidence:  2

Gaps (must resolve before closing story):
  <STORY-ID>-1: Add Apidog contract link
  <STORY-ID>-3: Add Confluence page link

============================================================
Status: NOT READY — 2 evidence gaps
```

Print `Status: READY` only when all closed sub-tasks have all required evidence.

## Common mistakes

| Mistake | Fix |
|---|---|
| Checking only closed tasks | Check all tasks — evidence should be added when work is done, not at close time |
| Treating a PR draft as sufficient | Only merged PRs count as evidence for backend/frontend tasks |
| Skipping test tasks | Test tasks need a CI link or test report, not just a PR |
