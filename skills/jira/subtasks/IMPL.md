---
name: create-story-tasks
description: Use after test-plan is approved to create Jira sub-tasks before implementation starts. Also use when adding a new sub-task mid-implementation for spec changes or bug fixes.
---

# Create Story Tasks

## Overview

Read `openspec-tasks.md` (or `plan.md` fallback) → present estimates to user → create Jira sub-tasks (with assignee + estimate) → write sub-task IDs to `jira-subtasks.md` → transition sub-tasks to In Progress when work starts.

## Gate position

```
/testing-plan <STORY-ID>   ← must run first
/jira-subtasks <STORY-ID>  ← this skill
Implementation starts
```

## Prerequisites

- `./docs/stories/<STORY-ID>-<slug>/test-plan.md` approved
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

### Step 4 — Write sub-task IDs to jira-subtasks.md

Write to `./docs/stories/<STORY-ID>-<slug>/jira-subtasks.md` (NOT plan.md):

```markdown
## Jira Sub-task IDs

| Sub-task | Jira | Summary |
|---|---|---|
| T1 | [VOR-XXXXX](https://vivotek.atlassian.net/browse/VOR-XXXXX) | Summary of task 1 |
| T2 | [VOR-XXXXX](https://vivotek.atlassian.net/browse/VOR-XXXXX) | Summary of task 2 |
```

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

Before starting each sub-task, transition it to In Progress. After completing, transition to Done. Do NOT batch all transitions at the end.

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER") || exit 1

SUBTASK_ID="VOR-XXXXX"   # the sub-task being started

# Get transitions for this sub-task
curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$SUBTASK_ID/transitions" \
  | python3 -c "import json,sys; [print(t[\"id\"], t[\"name\"]) for t in json.load(sys.stdin)[\"transitions\"]]"

# Transition to In Progress (or Done when complete)
curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  -X POST -H "Content-Type: application/json" \
  "https://$JIRA_HOST/rest/api/2/issue/$SUBTASK_ID/transitions" \
  -d "{\"transition\":{\"id\":\"<TRANSITION_ID>\"}}"
unset _JIRA_PASS
```

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
