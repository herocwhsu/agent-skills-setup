---
name: create-story-tasks
description: Use after writing-plans is approved to create Jira sub-tasks before implementation starts. Also use when adding a new sub-task mid-implementation for spec changes or bug fixes.
---

# Create Story Tasks

## Overview

Read `openspec-tasks.md` (or `plan.md` fallback) → group into PR-shaped flows → write `pr-plan.md` → present estimates → create Jira sub-tasks (impl `T<n>` + uat companion `U<n>`) → write IDs to `jira-subtasks.md` and `pr-plan.md` → transition sub-tasks to In Progress when work starts.

## Sub-task ID convention

- **T\<n>** — implementation sub-task in the primary repo
- **U\<n>** — uat / API-test companion sub-task in the test repo. Number matches the **PR group**, not the T number (so PR group 2 owns U2 even if it implements T4)
- **R\<n>** — refactor PR row in `pr-plan.md`. R-rows are not Jira sub-tasks; they are landed as no-op PRs before the flow PR they enable

Sub-task summaries do NOT include the `[STORY-ID N/M]` prefix — Jira already nests sub-tasks under their parent. The prefix lives on **GitHub PR titles only**, where it carries ordering across an unstructured PR list.

## Gate position

```
/testing-plan <STORY-ID>      ← test plan approved
/brainstorming <topic>        ← design decisions confirmed
/writing-plans <STORY-ID>     ← implementation plan approved
/jira-subtasks <STORY-ID>     ← this skill (sub-tasks + pr-plan.md)
/testing-write <STORY-ID>     ← (separate skill) creates U<n> test PRs
Implementation starts
```

Sub-tasks are created from the approved implementation plan, not before it. Creating them earlier means they won't match what gets built.

## Prerequisites

- `./docs/superpowers/plans/<plan>.md` approved by user
- Jira credentials in keychain
- `JIRA_PROJECT_KEY` set in `~/.agent-skills-setup/config.sh`

## Workflow

### Step 0 — Load config

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
[[ -z "${JIRA_HOST:-}" ]]        && { echo "ERROR: JIRA_HOST not set" >&2; exit 1; }
[[ -z "${JIRA_USER:-}" ]]        && { echo "ERROR: JIRA_USER not set" >&2; exit 1; }
[[ -z "${JIRA_PROJECT_KEY:-}" ]] && { echo "ERROR: JIRA_PROJECT_KEY not set" >&2; exit 1; }
```

### Step 1 — Derive tasks from OpenSpec or plan

Read tasks from (in order, use first that exists):
1. `./docs/stories/<STORY-ID>-<slug>/openspec-tasks.md` — canonical post-OpenSpec source
2. `./docs/stories/<STORY-ID>-<slug>/plan.md` — legacy fallback

Group tasks into logical sub-tasks (one sub-task per major section, not one per checklist item).

### Step 1.5 — Group sub-tasks into PRs by user flow

After deriving sub-tasks but BEFORE asking for estimates, propose PR groupings.

**Rules for grouping:**

1. **Identify user-facing flows.** A flow = an end-to-end user walkthrough. Multi-step API contracts (e.g. SRP login = 2 calls + challenge) are one flow, not multiple PRs.
2. **One flow = one PR.** Splitting a flow leaves reviewers reading partial contracts.
3. **Plumbing groups separately.** Foundation/refactor work has no flow — it gets its own PR (typically the first one).
4. **Refactor PRs land first**, before the flow PR that needs them. Output them as a separate row prefixed `R<n>` with no Jira sub-tasks attached.
5. **Companion test sub-task per flow PR.** Created in the test repo's Jira project as `U<n>` (matches the PR group number). Plumbing-only PRs may have no U-task — note `n/a` and justify.
6. **Each PR ≤ 5 days estimate.** If a flow PR exceeds budget, split by endpoint group within the flow.
7. **Dependencies are explicit but not strictly linear.** Flow PR 4/4 may depend only on PR 1/4, not 3/4 — declare what each row actually waits on so independent flows can ship in parallel.

**Present the proposed grouping table to the user** before creating any Jira tickets:

```
Proposed PR groupings for <STORY-ID>:

| PR | Title prefix | Impl sub-tasks | uat sub-task | Refactor first | Depends on |
|---|---|---|---|---|---|
| 1/4 | [STORY-ID 1/4] foundation + pentest fix | T1, T3 | n/a (plumbing) | R1 | — |
| 2/4 | [STORY-ID 2/4] login flow | T4 | U2 | none | 1/4 |
| 3/4 | [STORY-ID 3/4] session ops + ops | T5a, T7 | U3 | none | 2/4 |
| 4/4 | [STORY-ID 4/4] forgot password | T5b | U4 | none | 1/4 |

Confirm or describe re-grouping (e.g. "merge 3/4 and 4/4", "split 2/4 by endpoint").
I won't create Jira tickets until you confirm.
```

Once confirmed, write the table to `./docs/stories/<STORY-ID>-<slug>/pr-plan.md` before proceeding to Step 2. Use `templates/pr-plan-template.md` (in this skill's directory) as the starting structure.

### Step 2 — Ask user for estimates before creating

Present the proposed sub-task list and ask the user to confirm or adjust estimates before creating anything. Use `timetracking.originalEstimate` string format: `"1d"`, `"2d"`, `"0.5d"`, `"4h"`.

### Step 3 — Create sub-tasks with assignee + estimate

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1

STORY_ID="VOR-XXXXX"   # replace with actual story ID

SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER") || exit 1

# Get current user accountId for assignee
ACCOUNT_ID=$(curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  "https://$JIRA_HOST/rest/api/2/myself" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)[\"accountId\"])")

create_subtask() {
  local summary="$1"
  local description="$2"
  local estimate="$3"
  curl -s -u "$JIRA_USER:$_JIRA_PASS" \
    -X POST -H "Content-Type: application/json" \
    "https://$JIRA_HOST/rest/api/2/issue" \
    -d "{
      \"fields\": {
        \"project\":      {\"key\": \"$JIRA_PROJECT_KEY\"},
        \"parent\":       {\"key\": \"$STORY_ID\"},
        \"issuetype\":    {\"name\": \"Sub-task\"},
        \"summary\":      \"$summary\",
        \"description\":  \"$description\",
        \"assignee\":     {\"accountId\": \"$ACCOUNT_ID\"},
        \"timetracking\": {\"originalEstimate\": \"$estimate\"}
      }
    }" | python3 -c "
import json,sys
d=json.load(sys.stdin)
key = d.get(\"key\")
if key:
    print(key)
else:
    print(\"ERROR:\", d.get(\"errorMessages\", d))
"
}

# Call create_subtask once per logical group:
T1=$(create_subtask "Summary of task 1" "Description. Branch: $STORY_ID" "2d")
echo "T1: $T1"
# ... repeat for T2, T3, etc.

unset _JIRA_PASS
```

**Important notes on description strings:**
- Never use unescaped double quotes inside description — omit them or use single quotes in the text
- Keep descriptions concise; long descriptions with special chars cause JSON parse errors

### Step 4 — Write sub-task IDs to jira-subtasks.md and pr-plan.md

`pr-plan.md` already exists from Step 1.5 with placeholder sub-task names. Update it now to fill in the created Jira IDs.

Write `./docs/stories/<STORY-ID>-<slug>/jira-subtasks.md` (NOT plan.md) with a `PR group` column so the PR-to-Jira mapping is explicit:

```markdown
## Jira Sub-task IDs

| Sub-task | Jira | PR group | Summary |
|---|---|---|---|
| T1 | [VOR-XXXXX](https://vivotek.atlassian.net/browse/VOR-XXXXX) | 1/4 | Backend plumbing — tenant config, cookie helper, errors |
| T3 | [VOR-XXXXX](https://vivotek.atlassian.net/browse/VOR-XXXXX) | 1/4 | token_use claim validation in DecodeJWT (pentest fix) |
| T4 | [VOR-XXXXX](https://vivotek.atlassian.net/browse/VOR-XXXXX) | 2/4 | /auth/login + /auth/login-respond + /auth/password-force-change |
| U2 | [VOR-XXXXX](https://vivotek.atlassian.net/browse/VOR-XXXXX) | 2/4 | reseller-uat — SRP login + force-change cookie flow tests |
```

`U<n>` rows reference Jira tickets in the **test repo's project** (e.g. for reseller-uat work, the project key may differ from `JIRA_PROJECT_KEY`). The `/testing-write` skill creates those — `/jira-subtasks` only **names** them in `pr-plan.md` so reviewers see the contract.

### Step 5 — Transition parent story to In Progress

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER") || exit 1

STORY_ID="VOR-XXXXX"

# List available transitions
curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$STORY_ID/transitions" \
  | python3 -c "import json,sys; [print(t[\"id\"], t[\"name\"]) for t in json.load(sys.stdin)[\"transitions\"]]"

# Apply In Progress transition (use ID from list above)
curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  -X POST -H "Content-Type: application/json" \
  "https://$JIRA_HOST/rest/api/2/issue/$STORY_ID/transitions" \
  -d "{\"transition\":{\"id\":\"<IN_PROGRESS_ID>\"}}"
unset _JIRA_PASS
```

### Step 6 — Transition individual sub-tasks as work proceeds

Before starting each sub-task → **In Progress** (21). After code is complete and committed → **Done** (31). Done = code-complete, not merged. Do NOT wait for human review before marking Done.

After each sub-task is Done, add a completion comment with the commit SHA and what was done. Description must not contain unescaped double quotes:

```bash
bash -c '
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER") || exit 1

# Transition sub-task (21=In Progress, 31=Done)
curl -s -o /dev/null -w "%{http_code}" \
  -u "$JIRA_USER:$_JIRA_PASS" \
  -X POST -H "Content-Type: application/json" \
  "https://$JIRA_HOST/rest/api/2/issue/VOR-XXXXX/transitions" \
  -d "{\"transition\":{\"id\":\"31\"}}"

# Add completion comment
curl -s -o /dev/null -w " %{http_code}" \
  -u "$JIRA_USER:$_JIRA_PASS" \
  -X POST -H "Content-Type: application/json" \
  "https://$JIRA_HOST/rest/api/2/issue/VOR-XXXXX/comment" \
  -d "{\"body\": \"Fixed in commit <sha>. <description — no double quotes.>\"}"
unset _JIRA_PASS
'
```

### Step 7 — Create summary sub-task per PR group, request human review

Once all sub-tasks **for one PR group** are Done, create ONE summary sub-task that links **that PR**. This is the human review gate for that group — not for the whole story.

For a story with N PR groups you create N summary sub-tasks, each at the time the corresponding PR opens. Do NOT wait for all groups to complete before review — that defeats the point of splitting.

```bash
# Summary sub-task fields (one per PR group):
# summary:     "[PR#NNN] <PR title without [STORY-ID N/M] prefix>"
# description: PR URL + branch + commit SHAs in this group + which T<n>/U<n> sub-tasks are covered
# estimate:    "0d" (tracking artifact, no estimate)
```

The GitHub PR title carries `[STORY-ID N/M]`; the Jira summary repeats the PR number `[PR#NNN]` so reviewers can navigate either direction. Do not duplicate `[STORY-ID N/M]` into the Jira summary — Jira already nests under the parent story.

Then run automated code review (superpowers:requesting-code-review), fix any Critical/Important findings, and transition the summary sub-task AND parent story to **CODE REVIEW / TRACKING** (41):

```bash
bash -c '
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER") || exit 1

for ISSUE in "VOR-SUMMARY-ID" "VOR-PARENT-ID"; do
  curl -s -o /dev/null -w "$ISSUE: %{http_code} " \
    -u "$JIRA_USER:$_JIRA_PASS" \
    -X POST -H "Content-Type: application/json" \
    "https://$JIRA_HOST/rest/api/2/issue/$ISSUE/transitions" \
    -d "{\"transition\":{\"id\":\"41\"}}"
done
unset _JIRA_PASS
'
```

After human approves and PR merges → move summary sub-task + parent story to **Done** (31).

**Why this pattern:** Sub-tasks track implementation progress. Human review happens once **per PR group**, not once per sub-task and not once per story. Per-sub-task review blocks each one sequentially and wastes the reviewer's time. Per-story review forces reviewers to read 6k+ lines in one sitting. Per-PR-group review balances both — each PR is reviewable in one sitting and the story ships in independently mergeable slices.

## Adding a Task Mid-Implementation

1. Create one new Jira sub-task using Step 3 above
2. Append entry to `jira-subtasks.md`
3. Run `/review-amend` if the new task reflects a spec change

## Common Mistakes

| Mistake | Fix |
|---|---|
| `JIRA_PROJECT_KEY not in config.sh` | Run `bash scripts/credentials/service.sh jira add` |
| `timeoriginalestimate` (seconds) returns 400 | Use `timetracking.originalEstimate` string (`"2d"`) instead |
| Description with double quotes breaks JSON | Remove quotes or use single quotes in description text |
| `assignee` not set — using username instead of accountId | Fetch accountId via `GET /rest/api/2/myself` and use that |
| `_store.sh` / `read_credential` not found in zsh | Fixed in lib.sh — `source ~/.agent-skills-setup/lib.sh` works in both bash and zsh |
| Writing sub-task IDs to `plan.md` | Write to `jira-subtasks.md` in the story folder instead |
| Transitioning all sub-tasks to Done at end of sprint | Transition each sub-task individually as work starts/completes |
| Creating sub-tasks before grouping into PRs | Run Step 1.5 first; the grouping changes how many sub-tasks you actually need |
| One giant PR for the whole story | Default to multi-PR plan in `pr-plan.md`; only collapse to one PR if the story is genuinely a single user-facing flow |
| Cramming `[STORY-ID N/M]` into Jira sub-task summary | Prefix lives on GitHub PR titles only; Jira nests sub-tasks under the parent already |
| Skipping U\<n\> companion test sub-task | Required for every flow PR. Justify `n/a` only for plumbing-only PRs |
| Mid-impl refactor commits inside a flow PR | Land refactor as a separate `R<n>` PR first, then rebase the flow PR on it |
