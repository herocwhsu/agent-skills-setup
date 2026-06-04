---
subcommand: regression
group: testing
slash: /testing-regression <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/regression-tests.md
---

# testing/regression — Regression Test Generator

Generates regression tests for a bugfix or change request. Workflow spec §12.3:
"No regression test, no bugfix closure."

## When to run

- A `change-requests/` file has been created (`/review-change-request`)
- A `release/bugfix/<BUG-ID>-<slug>/` has been created (`/release-bugfix-spec`)
- Any behavior is changing that could break existing functionality

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

Read the trigger artifact:
- `$STORY_DIR/change-requests/<date>-<slug>.md` — or
- `$STORY_DIR/release/bugfix/<BUG-ID>-<slug>/bugfix-spec.md`

## For each changed behavior, define

1. **What was the old behavior?** (from the bugfix spec or change request)
2. **What is the new correct behavior?**
3. **How to verify the fix?** (test code or manual step)
4. **What else could this break?** (regression scope)

## Output format

Write to `$STORY_DIR/regression-tests.md` (or inside the bugfix folder):

```markdown
---
story: <JIRA-ID>
trigger: change-request | bugfix
trigger_file: <path>
created_at: <YYYY-MM-DD>
---

# Regression Tests: <JIRA-ID>

## Bug / Change Summary
<one paragraph from the trigger artifact>

## Regression Test Cases

### RT-001: <behavior that must now work correctly>
- **Given:** <precondition>
- **When:** <action>
- **Then:** <expected result — the fixed behavior>
- **Previously:** <what was happening before the fix>

### RT-002: <existing behavior that must not regress>
- **Given:** <precondition>
- **When:** <action>
- **Then:** <expected result — must remain unchanged>

## Affected Areas
- `<file or module>` — <why affected>

## Verification Command
```bash
# Run the relevant test suite
go test ./... -run TestXxx
```
```
