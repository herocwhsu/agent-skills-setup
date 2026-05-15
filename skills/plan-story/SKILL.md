---
name: plan-story
description: Use when a Jira story has been fetched to ./docs/stories/<ID>/ and needs an implementation plan. Invokes brainstorming then writing-plans automatically, produces plan.md with tasks, dependencies, and branch names.
---

# Plan Story

## Overview

Read fetched story docs → brainstorm requirements → write implementation plan → save `plan.md`.

**REQUIRED SUB-SKILLS:** Invokes `brainstorming` then `writing-plans` in sequence.

## Prerequisites

`./docs/stories/<STORY-ID>/story.md` must exist (run `fetch-jira-story` first).

## Output

```
./docs/stories/VOR-29600/
  plan.md    ← tasks, dependencies, branch names, acceptance criteria
```

## Workflow

### Step 1 — Read all story docs

Read every file in `./docs/stories/<STORY-ID>/`:
- `story.md` — requirements and links
- `confluence-*.md` — referenced specs
- `apidog-*.md` — API references

### Step 2 — Brainstorm (invoke brainstorming skill)

Read `~/.kiro/skills/brainstorming/SKILL.md` and follow it.

Focus on:
- What does this story require technically?
- What are the unknowns or risks?
- What are the natural task boundaries?
- What dependencies exist between tasks?

Produce a spec section in `plan.md`.

### Step 3 — Write plan (invoke writing-plans skill)

Read `~/.kiro/skills/writing-plans/SKILL.md` and follow it.

Each task in the plan must include:

| Field | Description |
|---|---|
| `id` | Sequential: T1, T2, T3... |
| `title` | Short description |
| `branch` | `<STORY-ID>-t<N>` e.g. `VOR-29600-t1` |
| `depends_on` | List of task IDs that must merge first (empty if none) |
| `description` | What to implement |
| `acceptance` | How to verify done (tests pass, code review, fits spec) |

### Step 4 — Save plan.md

```markdown
# VOR-29600 Implementation Plan

## Spec Summary
[brainstorming output]

## Tasks

### T1: <title>
- **Branch:** VOR-29600-t1
- **Depends on:** none
- **Description:** ...
- **Acceptance:** all tests pass, code review approved, fits spec

### T2: <title>
- **Branch:** VOR-29600-t2
- **Depends on:** T1
- **Description:** ...
- **Acceptance:** ...

## Jira Sub-task IDs
<!-- populated by create-story-tasks -->
```

### Step 5 — Confirm with user

Present the plan. Ask: "Does this plan look correct? Any changes before creating Jira sub-tasks?"

Do NOT proceed to `create-story-tasks` until user confirms.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping brainstorming | Always read brainstorming skill first — requirements need exploration |
| Tasks too large | Each task should be implementable in one PR without blocking others |
| Missing dependencies | If T2 imports T1's code, mark `depends_on: T1` |
| Branch name conflicts | Always prefix with story ID: `VOR-29600-t1` not just `t1` |
