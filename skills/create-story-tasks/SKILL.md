---
name: create-story-tasks
description: Use after plan-story is confirmed to create Jira sub-tasks and git worktrees. Also use when adding a new sub-task mid-implementation for spec changes or bug fixes.
---

# Create Story Tasks

## Overview

Read confirmed `plan.md` → create Jira sub-tasks via API → write sub-task IDs back to plan → create git worktrees in dependency order.

## Prerequisites

- `./docs/stories/<STORY-ID>/plan.md` confirmed by user
- Jira credentials in keychain (same as `fetch-jira-story`)
- Clean git state on main branch

## Workflow

### Step 1 — Create Jira sub-tasks

For each task in plan.md:

```bash
STORY_ID="EXAMPLE-100"
JIRA_HOST="example-org.atlassian.net"
SLUG="jira-$(echo "$JIRA_HOST" | sed 's/[^a-zA-Z0-9]/-/g;s/-\+/-/g;s/-$//')"

read -rp "Jira username (email): " _JIRA_USER
_JIRA_PASS=$(security find-generic-password -s "agent-skills:$SLUG" -a "$_JIRA_USER" -w 2>/dev/null)

# Create sub-task
curl -s -u "$_JIRA_USER:$_JIRA_PASS" \
  -X POST \
  -H "Content-Type: application/json" \
  "https://$JIRA_HOST/rest/api/2/issue" \
  -d "{
    \"fields\": {
      \"project\": {\"key\": \"VOR\"},
      \"parent\": {\"key\": \"$STORY_ID\"},
      \"issuetype\": {\"name\": \"Sub-task\"},
      \"summary\": \"<task title>\",
      \"description\": \"<task description>\nBranch: <branch-name>\"
    }
  }" > /tmp/_jira_subtask.json
unset _JIRA_PASS

# Extract created sub-task ID
python3 -c "import json; d=json.load(open('/tmp/_jira_subtask.json')); print(d['key'])"
```

### Step 2 — Write sub-task IDs back to plan.md

Update the `## Jira Sub-task IDs` section in plan.md:

```markdown
## Jira Sub-task IDs
- T1 → EXAMPLE-101
- T2 → EXAMPLE-102
- T3 → EXAMPLE-103
```

### Step 3 — Create git worktrees

For each task, in dependency order (tasks with no dependencies first):

```bash
# From repo root
BRANCH="EXAMPLE-100-t1"
git worktree add "../$(basename $(pwd))-$BRANCH" -b "$BRANCH"
echo "Worktree created: ../<repo>-$BRANCH"
```

**Dependency rule:** Only create a worktree for T2 if T1 has no blocking dependency that prevents parallel work. If T2 strictly requires T1's merged code, note it in plan.md and create T2's worktree after T1 merges.

**Read `using-git-worktrees` skill** for full worktree workflow:
`~/.kiro/skills/using-git-worktrees/SKILL.md`

### Step 4 — Report

Print summary:
```
✓ EXAMPLE-100-t1 → Jira: EXAMPLE-101 → worktree: ../repo-EXAMPLE-100-t1
✓ EXAMPLE-100-t2 → Jira: EXAMPLE-102 → worktree: ../repo-EXAMPLE-100-t2 (after T1 merges)
```

## Adding a Task Mid-Implementation

For spec changes or bug fixes during implementation:

```
@add-task EXAMPLE-100 "fix: description of new task"
```

1. Create one new Jira sub-task under the story
2. Add new task entry to plan.md (next T-number)
3. Create one new git worktree for the branch
4. Report the new sub-task ID and worktree path

## Common Mistakes

| Mistake | Fix |
|---|---|
| Creating T2 worktree before T1 merges (when T2 depends on T1) | Check `depends_on` in plan.md; wait or note the dependency |
| Jira project key wrong | Extract from story ID: `EXAMPLE-100` → project key `VOR` |
| Sub-task type not available | Check project config; use `"Task"` if `"Sub-task"` not configured |
| Worktree path conflicts | Use `git worktree list` to check existing worktrees |
| Dirty git state | Run `git status` first; stash or commit before creating worktrees |
