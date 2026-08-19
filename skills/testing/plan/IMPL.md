---
subcommand: plan
group: testing
slash: /testing-plan <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/test-plan.md
---

# testing/plan — Test Plan Generator

Generates a comprehensive test plan from OpenSpec acceptance criteria, the
Apidog contract, and repo context. Created before implementation starts.

Corresponds to workflow spec §14.8, skill 23.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

Read (in order, use what's available):
1. `./openspec/changes/<change-id>/specs/` — acceptance scenarios
2. `$STORY_DIR/apidog/contract.md` — API test cases source
3. `$STORY_DIR/apidog/testcases.md` — pre-generated test cases to include
4. `$STORY_DIR/story.md` — fallback if OpenSpec not yet created

## Derive the change-id

```bash
JIRA_ID="$1"
# Read from intake-summary.md frontmatter if available
CHANGE_ID=$(grep "^  - " "$STORY_DIR/intake-summary.md" 2>/dev/null | head -1 | sed 's/^  - //')
# Fallback: derive from story.md title
[[ -z "$CHANGE_ID" ]] && CHANGE_ID="${JIRA_ID,,}-$(story_slug_from_summary "$(grep '^# ' "$STORY_DIR/story.md" | head -1 | sed 's/^# [A-Z0-9-]*: //')")"
```

## Step 0.5 — Decide sequential vs parallel drafting

Count the distinct API endpoints (from `apidog/contract.md`) or acceptance
criteria (from the OpenSpec specs) this story covers.

- **Fewer than 3:** draft all sections below yourself, sequentially.
- **3 or more:** dispatch one sub-task per endpoint/acceptance-criterion to
  draft that unit's Unit/Integration/API test rows in isolation. Give each
  sub-task only its own contract entry or acceptance-criterion text plus the
  matching test pattern from `repo-context.md`. Use whatever native
  sub-agent/delegation mechanism this host provides. Merge each sub-task's
  rows into the tables below, in the same order as `apidog/contract.md` or
  the acceptance criteria list, before writing `test-plan.md`.

  Do not split the **Regression Coverage** and **Manual QA Checklist**
  sections this way — those need a single pass over the whole story to
  catch cross-cutting effects between endpoints; splitting them per-unit
  would miss interactions.

## Test plan sections

### Unit tests
- List each function/method that needs a unit test
- Focus on: business logic, validation, edge cases
- Do NOT list tests for trivial getters/setters

### Integration tests
- List each service boundary that needs an integration test
- Focus on: DB queries, permission middleware, external adapters
- Reference existing test patterns from `repo-context.md`

### API tests
- Map directly from `apidog/testcases.md` (if exists) or `apidog/contract.md`
- Include each test case category: positive, negative, boundary, permission

### Regression test plan
- List any existing behavior that this change could break
- Reference existing tests that should continue to pass

### Manual QA checklist
- User-visible behavior that requires manual verification
- Edge cases that are hard to automate

## Output format

Write to `$STORY_DIR/test-plan.md`:

```markdown
---
story: <JIRA-ID>
openspec_change: <change-id>
created_at: <YYYY-MM-DD>
status: draft
---

# Test Plan: <JIRA-ID>

## Unit Tests

| Test | File | Priority |
|---|---|---|
| <function> handles empty input | `<package>/<file>_test` | High |

## Integration Tests

| Test | Scope | Priority |
|---|---|---|
| Permission middleware rejects tenant-B | Middleware + DB | High |

## API Tests

Sourced from `apidog/testcases.md`:
- TC-001: Happy path — ...
- TC-002: Missing auth token — ...
[full list]

## Regression Coverage

| Existing behavior | Test file | Risk |
|---|---|---|
| List cameras still paginates correctly | `camera_test.go:TestListCameras` | Medium |

## Manual QA Checklist

- [ ] <user-visible behavior 1>
- [ ] <user-visible behavior 2>

## Coverage Summary

| Layer | Test count | Acceptance criteria covered |
|---|---|---|
| Unit | | |
| Integration | | |
| API | | |
| Manual | | |
```
