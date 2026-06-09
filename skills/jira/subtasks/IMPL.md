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
- `JIRA_PROJECT_KEY` set in `~/.agent-skills-setup/config.sh`
- Clean git state on main branch

## Workflow

### Step 1 — Create Jira sub-tasks

For each task in plan.md:

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1

[[ -z "${JIRA_HOST:-}" ]] && { echo "ERROR: JIRA_HOST not in config.sh" >&2; exit 1; }
[[ -z "${JIRA_USER:-}" ]] && { echo "ERROR: JIRA_USER not in config.sh" >&2; exit 1; }
[[ -z "${JIRA_PROJECT_KEY:-}" ]] && { echo "ERROR: JIRA_PROJECT_KEY not in config.sh — run: bash scripts/credentials/service.sh jira add" >&2; exit 1; }

STORY_ID="$1"   # e.g. PROJ-123

SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER" "bash scripts/credentials/service.sh jira add") || exit 1

# Create sub-task
curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  -X POST \
  -H "Content-Type: application/json" \
  "https://$JIRA_HOST/rest/api/2/issue" \
  -d "{
    \"fields\": {
      \"project\": {\"key\": \"$JIRA_PROJECT_KEY\"},
      \"parent\": {\"key\": \"$STORY_ID\"},
      \"issuetype\": {\"name\": \"Sub-task\"},
      \"summary\": \"<task title>\",
      \"description\": \"<task description>\\nBranch: <branch-name>\"
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
- T1 → <STORY-ID>-1
- T2 → <STORY-ID>-2
- T3 → <STORY-ID>-3
```

(The actual returned keys come from Jira; the format depends on your project's numbering.)

### Step 3 — Create git worktrees

For each task, in dependency order (tasks with no dependencies first):

```bash
# From repo root
BRANCH="$STORY_ID-t1"
git worktree add "../$(basename $(pwd))-$BRANCH" -b "$BRANCH"
echo "Worktree created: ../<repo>-$BRANCH"
```

**Dependency rule:** Only create a worktree for T2 if T1 has no blocking dependency that prevents parallel work. If T2 strictly requires T1's merged code, note it in plan.md and create T2's worktree after T1 merges.

**Invoke using-git-worktrees sub-skill** for full worktree workflow:
- **Claude Code:** Use the `Skill` tool with skill name `superpowers:using-git-worktrees`
- **Kiro:** Read `~/.kiro/skills/using-git-worktrees/SKILL.md` and follow it

### Step 4 — Report

Print summary:
```
✓ <STORY-ID>-t1 → Jira: <SUBTASK-1> → worktree: ../repo-<STORY-ID>-t1
✓ <STORY-ID>-t2 → Jira: <SUBTASK-2> → worktree: ../repo-<STORY-ID>-t2 (after T1 merges)
```

### Step 5 — Transition parent story to In Progress

After sub-tasks are created, transition the parent story to In Progress so Jira reflects that work has started:

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER") || exit 1

# Get available transitions
curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$STORY_ID/transitions" \
  | python3 -c "import json,sys; [print(f\"{t['id']}: {t['name']}\") for t in json.load(sys.stdin)['transitions']]"

# Transition to In Progress (find the correct ID from the list above)
curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  -X POST -H "Content-Type: application/json" \
  "https://$JIRA_HOST/rest/api/2/issue/$STORY_ID/transitions" \
  -d '{"transition":{"id":"<IN_PROGRESS_TRANSITION_ID>"}}'
unset _JIRA_PASS
```

**Important:** Each sub-task should also be transitioned to **In Progress** when you start working on it, and to **Done** when it is complete. Do not wait until all work is done — update sub-task status as you go so Jira reflects live progress.

## Adding a Task Mid-Implementation

For spec changes or bug fixes during implementation:

```
@add-task <STORY-ID> "fix: description of new task"
```

1. Create one new Jira sub-task under the story
2. Add new task entry to plan.md (next T-number)
3. Create one new git worktree for the branch
4. Report the new sub-task ID and worktree path

## Common Mistakes

| Mistake | Fix |
|---|---|
| `JIRA_PROJECT_KEY not in config.sh` | Run `bash scripts/credentials/service.sh jira add` |
| Creating T2 worktree before T1 merges (when T2 depends on T1) | Check `depends_on` in plan.md; wait or note the dependency |
| Sub-task type not available | Check project config; use `"Task"` if `"Sub-task"` not configured |
| Worktree path conflicts | Use `git worktree list` to check existing worktrees |
| Dirty git state | Run `git status` first; stash or commit before creating worktrees |
