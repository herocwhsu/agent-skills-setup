---
subcommand: amend
group: review
slash: /review-amend <STORY-ID> <slug>
output: ./docs/stories/<JIRA-ID>-<slug>/amendments/YYYY-MM-DD-<slug>.md
---

# review/amend — Spec Amendment Writer

Captures a small spec change during implementation. Use when the change is
minor — wording, field clarification, edge case, minor acceptance criteria update.

Workflow spec §10.1 + §10.3 decision rule:
```
Small wording, field, or edge-case clarification → Amendment
API, DB, permission, behavior, scope, or test baseline change → Change Request
```

## When to use

Examples of AMENDMENTS (small, no downstream impact):
- Wording clarification
- Small field clarification (rename, description update)
- Additional edge case documented
- Minor acceptance criteria wording update
- Small error message clarification

Examples that should be CHANGE REQUESTS instead:
- API contract changed → use `/review-change-request`
- DB schema changed → use `/review-change-request`
- Permission model changed → use `/review-change-request`
- Scope changed → use `/review-change-request`

If unsure, use `/review-change-request` — it costs more process but preserves information.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
STORY_DIR=$(resolve_story_dir "$1") || exit 1
SLUG="$2"  # e.g. "clarify-cursor-format"
DATE=$(date +%Y-%m-%d)
OUT="$STORY_DIR/amendments/${DATE}-${SLUG}.md"
mkdir -p "$STORY_DIR/amendments"
```

## Output format

Write to `$STORY_DIR/amendments/<YYYY-MM-DD>-<slug>.md`:

```markdown
---
story: <JIRA-ID>
amendment_date: <YYYY-MM-DD>
slug: <slug>
affects: proposal | tasks | acceptance | apidog | tests
---

# Amendment: <JIRA-ID> — <slug>

## Change
<what is being clarified or updated — one paragraph>

## Before
<previous wording or understanding>

## After
<new wording or understanding>

## Why
<reason discovered during implementation>

## Impact
- OpenSpec proposal section: <which section to update, or "none">
- Apidog: <update needed? yes/no — if yes, which field>
- Tests: <update needed? yes/no — if yes, which test>
- Jira sub-tasks: <update needed? yes/no>

## Classification: AMENDMENT
This is a small clarification. No API, DB, permission, or scope change.
If impact grows, promote to Change Request via /review-change-request.
```

Amendments are append-only. Never edit a previous amendment file — add a new one.
