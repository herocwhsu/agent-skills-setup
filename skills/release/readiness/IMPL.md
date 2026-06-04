---
subcommand: readiness
group: release
slash: /release-readiness <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/release/readiness.md
---

# release/readiness — Release Readiness Checker

Verifies all gates have passed before releasing a feature. No guesswork —
each check looks at actual artifacts in the story folder and OpenSpec.

Corresponds to workflow spec §14.11, skill 34.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

## Checks

For each check, inspect the actual artifact, not just whether the file exists.

### Gate 1: OpenSpec

```bash
CHANGE_ID=<derived from intake-summary.md>
SPEC_DIR="./openspec/changes/$CHANGE_ID"
ARCHIVE_DIR="./openspec/changes/archive/"
```

| Check | Pass condition |
|---|---|
| OpenSpec proposal exists | `$SPEC_DIR/proposal.md` exists |
| OpenSpec tasks exist | `$SPEC_DIR/tasks.md` exists |
| OpenSpec not in draft | `proposal.md` frontmatter `status:` is not `draft` |
| OpenSpec applied | `/opsx:apply` has been run (tasks.md has no open `[ ]` items) |

### Gate 2: Jira

| Check | Pass condition |
|---|---|
| All sub-tasks closed | Run `gh issue list` or check Jira API for open sub-tasks |
| Evidence links present | PR link + CI link in each sub-task description |

### Gate 3: Apidog

| Check | Pass condition |
|---|---|
| API contract exists | `$STORY_DIR/apidog/contract.md` exists |
| Test cases exist | `$STORY_DIR/apidog/testcases.md` exists |

### Gate 4: Tests

| Check | Pass condition |
|---|---|
| Test plan exists | `$STORY_DIR/test-plan.md` exists |
| `/testing-qa-check` passed | Read `test-plan.md` for a pass marker (or run it now) |

### Gate 5: Documentation

| Check | Pass condition |
|---|---|
| Confluence updated | Story references a Confluence page with final behavior |

## Output format

Write to `$STORY_DIR/release/readiness.md`:

```markdown
---
story: <JIRA-ID>
checked_at: <YYYY-MM-DD>
status: ready | not-ready
blocking_count: <n>
---

# Release Readiness: <JIRA-ID>

## Gate Results

| Gate | Check | Status | Notes |
|---|---|---|---|
| OpenSpec | Proposal exists | ✓ / ✗ | |
| OpenSpec | Tasks applied | ✓ / ✗ | |
| Jira | All sub-tasks closed | ✓ / ✗ | |
| Jira | Evidence links present | ✓ / ✗ | |
| Apidog | Contract reviewed | ✓ / ✗ | |
| Tests | QA check passed | ✓ / ✗ | |
| Docs | Confluence updated | ✓ / ✗ | |

## Blocking Items
- [ ] <item 1>
- [ ] <item 2>

## Verdict
<READY TO RELEASE | NOT READY — N blocking items remain>
```

Set `status: ready` only when all checks pass and `blocking_count: 0`.
