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

The 5 sections below are dispatched as 5 parallel subagents in Step 2 (one section each). Each subagent marks every item: ✓ Present | ⚠ Partial | ✗ Missing | N/A Not applicable, and returns the marked checklist plus any gaps it identified. The main session merges the 5 results and classifies gaps in Step 3.

### Section 1 — Actors and scope
- [ ] Actor(s) clearly defined (who initiates each action)
- [ ] System boundaries clear (what is in scope vs out of scope)
- [ ] Non-goals explicitly stated

### Section 2 — Behavioral completeness
- [ ] Happy path described
- [ ] All error states described (4xx, 5xx, timeout, empty result)
- [ ] Permission/authorization behavior described for each action
- [ ] Edge cases covered (empty input, boundary values, concurrent access)
- [ ] Data validation rules stated

### Section 3 — API / data model
- [ ] Request/response schema defined or sketched
- [ ] Pagination behavior defined (if list endpoints)
- [ ] Sort/filter behavior defined (if applicable)
- [ ] Backward-compatibility constraints stated

### Section 4 — Acceptance criteria
- [ ] Each acceptance criterion is testable (Given/When/Then or equivalent)
- [ ] Acceptance criteria cover permission-denied cases
- [ ] Acceptance criteria cover error cases
- [ ] No criterion relies on unverifiable human judgment

### Section 5 — Conflicts and contradictions
- [ ] No conflicting requirements between Jira and Confluence
- [ ] No conflicting acceptance criteria within the same artifact
- [ ] Terminology used consistently throughout

## Step 1 — Read shared input artifacts

Read once, pass to every subagent:

1. `$STORY_DIR/story.md` — Jira description, acceptance criteria, linked tickets
2. `$STORY_DIR/confluence-*.md` — all Confluence reference pages (may be zero)
3. `$STORY_DIR/apidog-*.md` — all Apidog / public API reference pages (may be zero)
4. `$STORY_DIR/intake-summary.md` — if present, read last (Phase 2)

## Step 2 — Dispatch 5 subagents in parallel

Send all 5 Agent tool calls in a single message so they run concurrently. Each subagent runs as `general-purpose` with the same input bundle but a different `section` parameter (1–5). The system prompt instructs each subagent to mark its assigned section's items and return JSON in this exact shape:

```json
{
  "section_id": 1,
  "section_name": "Actors and scope",
  "checklist": [
    { "item": "Actor(s) clearly defined", "status": "Present" or "Partial" or "Missing" or "N/A", "evidence": "<short quote or location>" }
  ],
  "gaps": [
    { "id": "gap-1", "description": "what's missing", "found_in": "story.md | confluence-X.md | apidog-Y.md", "question_for": "PM | tech lead | QA" }
  ]
}
```

A subagent that finds no gaps returns `"gaps": []`. The main session must NOT abort if one subagent returns malformed JSON — log it, fall back to a stub `{"section_id": N, "checklist": [], "gaps": []}` for that section, and continue.

Why parallel:
- Each section reads the same artifacts but applies a different lens. Serial calls re-read identical input N times.
- Multi-section checklists in a single call dilute the model's attention on each section. One subagent per section keeps focus high.

## Step 3 — Classify gaps

After all 5 subagents return, the main session walks the merged `gaps[]` list and classifies each into one of:

| Class | Meaning | Action |
|---|---|---|
| `must-resolve` | Implementation cannot proceed without clarity | Block and ask PM / tech lead |
| `can-assume` | Safe to proceed with a named assumption | Document assumption in OpenSpec |
| `future-scope` | Valid enhancement but not for this story | Note in Non-goals |

Classification heuristics (apply in order):
1. Gap names a permission, security, or auth boundary → `must-resolve`.
2. Gap names a request/response field or DB schema field that's referenced by a checklist Missing → `must-resolve`.
3. Gap appears in story.md's "Out of scope" or Non-goals → `future-scope`.
4. Gap is a clarification of behavior with a sensible default → `can-assume`.
5. Otherwise → `must-resolve` (conservative default — `audit-handoff` won't pass with open must-resolves, which forces explicit triage).

## Step 4 — Write the audit report

Output schema unchanged from the original IMPL — written by the main session, not a subagent.

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
