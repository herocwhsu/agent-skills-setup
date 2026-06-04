---
subcommand: spec
group: audit
slash: /audit-spec <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/audit-report.md
---

# audit/spec — Spec Audit + Gap Detection

Reads intake artifacts for a story and produces a structured audit report
covering conflicts, missing behaviors, and gaps that must be resolved before
a viable OpenSpec proposal can be written.

This subcommand merges the responsibilities of spec-audit and gap-detector
from the workflow spec (§14.2, skills 4 and 5) — they always co-trigger on
the same input.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
```

Story folder must exist:
```bash
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

## Input artifacts (read in this order)

1. `$STORY_DIR/story.md` — Jira description, acceptance criteria, linked tickets
2. `$STORY_DIR/confluence-*.md` — all Confluence reference pages (may be zero)
3. `$STORY_DIR/apidog-*.md` — all Apidog / public API reference pages (may be zero)
4. `$STORY_DIR/intake-summary.md` — if it exists, read last (Phase 2)

## Audit checklist

For each item below, mark: ✓ Present | ⚠ Partial | ✗ Missing | N/A Not applicable

### Actors and scope
- [ ] Actor(s) clearly defined (who initiates each action)
- [ ] System boundaries clear (what is in scope vs out of scope)
- [ ] Non-goals explicitly stated

### Behavioral completeness
- [ ] Happy path described
- [ ] All error states described (4xx, 5xx, timeout, empty result)
- [ ] Permission/authorization behavior described for each action
- [ ] Edge cases covered (empty input, boundary values, concurrent access)
- [ ] Data validation rules stated

### API / data model
- [ ] Request/response schema defined or sketched
- [ ] Pagination behavior defined (if list endpoints)
- [ ] Sort/filter behavior defined (if applicable)
- [ ] Backward-compatibility constraints stated

### Acceptance criteria
- [ ] Each acceptance criterion is testable (Given/When/Then or equivalent)
- [ ] Acceptance criteria cover permission-denied cases
- [ ] Acceptance criteria cover error cases
- [ ] No criterion relies on unverifiable human judgment

### Conflicts and contradictions
- [ ] No conflicting requirements between Jira and Confluence
- [ ] No conflicting acceptance criteria within the same artifact
- [ ] Terminology used consistently throughout

## Gap classification

Classify each gap found as one of:

| Class | Meaning | Action |
|---|---|---|
| `must-resolve` | Implementation cannot proceed without clarity | Block and ask PM / tech lead |
| `can-assume` | Safe to proceed with a named assumption | Document assumption in OpenSpec |
| `future-scope` | Valid enhancement but not for this story | Note in Non-goals |

## Output format

Write to `$STORY_DIR/audit-report.md`:

```markdown
---
story: <JIRA-ID>
audited_at: <YYYY-MM-DD>
status: pass | needs-work
must_resolve_count: <n>
---

# Audit Report: <JIRA-ID>

## Summary
<2-3 sentence verdict. State the overall quality and whether the spec is
ready for OpenSpec proposal or needs work first.>

## Checklist Results
[table with each checklist item and its status]

## Gaps

### Must Resolve
- **GAP-1**: <description>
  - *Found in*: <artifact>
  - *Question for*: <PM / tech lead / QA>

### Can Assume
- **ASSUME-1**: <assumption statement>
  - *If wrong*: <impact>

### Future Scope
- **FUTURE-1**: <description>

## Recommended Next Steps
- [ ] Resolve GAP-1 before writing proposal
- [ ] Run /audit-domain-risk <STORY-ID>
- [ ] Run /audit-handoff <STORY-ID> when gaps are resolved
```

Set frontmatter `status: pass` only when there are zero `must-resolve` gaps.
`status: needs-work` otherwise.

## Common mistakes

| Mistake | Fix |
|---|---|
| Marking spec as `pass` with open must-resolve gaps | Only pass when every must-resolve item is either resolved or reclassified |
| Creating gaps for things that are clearly out of scope | Mark as N/A or future-scope, not a gap |
| Duplicating gaps from Jira and Confluence when they describe the same thing | Merge them, note both sources |
