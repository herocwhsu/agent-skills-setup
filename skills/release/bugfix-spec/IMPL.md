---
subcommand: bugfix-spec
group: release
slash: /release-bugfix-spec <ORIGINAL-STORY-ID> <BUG-JIRA-ID>
output: ./docs/stories/<ORIGINAL-STORY-ID>-<slug>/release/bugfix/<BUG-ID>-<slug>/bugfix-spec.md
---

# release/bugfix-spec — Bugfix Spec Generator

Converts a production bug into a structured bugfix spec with regression test
plan. Workflow spec §12.3 hard rule: "No regression test, no bugfix closure."

Corresponds to workflow spec §14.11, skill 36.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
BUG_ID="$2"
```

The bug should already exist as a Jira ticket. If not, create one first.
The original story folder must exist (run `/intake-jira-story` on the original
story if needed).

## Step 1 — Fetch the bug ticket

```bash
SLUG=$(service_slug jira "https://$JIRA_HOST")
_PASS=$(require_secret "$SLUG" "$JIRA_USER" "bash scripts/credentials/service.sh jira add") || exit 1

curl -s -u "$JIRA_USER:$_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$BUG_ID" \
  > /tmp/_bug_issue.json
unset _PASS
```

Extract: title, description, steps to reproduce, expected vs actual behavior.

## Step 2 — Compare against approved spec

Read `./openspec/changes/<change-id>/proposal.md` for the original story.
Identify exactly which acceptance criterion or behavior the bug violates.

## Step 3 — Derive change-id for the bugfix

```
BUG_CHANGE_ID="${BUG_ID,,}-fix-$(story_slug_from_summary "$BUG_TITLE" | cut -c1-30)"
# e.g. bug-2034-fix-permission-leak
```

## Step 4 — Write bugfix spec

Create the output directory:
```bash
BUG_DIR="$STORY_DIR/release/bugfix/${BUG_ID}-$(story_slug_from_summary "$BUG_TITLE" | cut -c1-30)"
mkdir -p "$BUG_DIR"
```

Write `$BUG_DIR/bugfix-spec.md`:

```markdown
---
original_story: <JIRA-ID>
bug_id: <BUG-ID>
openspec_change: <BUG_CHANGE_ID>
created_at: <YYYY-MM-DD>
---

# Bugfix Spec: <BUG-ID>

## Issue
<one-line description from Jira>

## Expected Behavior
<what the approved OpenSpec says should happen>

## Actual Behavior
<what is actually happening>

## Root Cause
<diagnosed root cause — if unknown, mark as "TBD, requires investigation">

## Fix Proposal
<what needs to change in the implementation>

## Regression Tests Required
<see regression-tests.md — must be written before this bug is closed>

## Affected Areas
- `<file or module>` — <why affected>
- Apidog test case: <TC number that should have caught this>
- Integration test: <existing test that should be updated>

## OpenSpec Change
This bugfix creates a new OpenSpec change: `<BUG_CHANGE_ID>`
Run: `/opsx:propose <BUG_CHANGE_ID>` with this spec as context.

## Post-Fix Steps
- [ ] Write regression test (`/testing-regression <ORIGINAL-STORY-ID>`)
- [ ] Create OpenSpec change for the fix (`/opsx:propose <BUG_CHANGE_ID>`)
- [ ] Update Apidog negative test case
- [ ] Verify with QA before closing bug ticket
```

## Step 5 — Print next steps

```
Bugfix spec created: <BUG_DIR>/bugfix-spec.md

Next steps:
  1. /testing-regression <ORIGINAL-STORY-ID>   ← write regression tests
  2. /opsx:propose <BUG_CHANGE_ID>             ← create OpenSpec change
  3. Implement the fix
  4. /release-readiness <ORIGINAL-STORY-ID>    ← verify before releasing patch
```
