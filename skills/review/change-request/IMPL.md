---
subcommand: change-request
group: review
slash: /review-change-request <STORY-ID> <slug>
output: ./docs/stories/<JIRA-ID>-<slug>/change-requests/YYYY-MM-DD-<slug>.md
---

# review/change-request — Change Request Writer

Captures a major spec change discovered during implementation. Use when API,
DB, permissions, behavior, scope, or test baseline is affected.

Merged: spec-change-impact-analyzer + change-request-writer + decision-log entry.
These three always co-trigger — you analyze the impact, write the request, and
record the decision in one flow.

Corresponds to workflow spec §14.9, skills 27–30 (merged).

## When to use

Use for:
- API contract changed (new/removed field, changed type, new endpoint)
- Database schema changed
- Permission model changed
- Product behavior changed
- Scope changed
- Release commitment changed
- Acceptance criteria changed significantly

If only wording or a small field clarification, use `/review-amend` instead.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
STORY_DIR=$(resolve_story_dir "$1") || exit 1
SLUG="$2"  # e.g. "add-site-filter"
DATE=$(date +%Y-%m-%d)
OUT="$STORY_DIR/change-requests/${DATE}-${SLUG}.md"
mkdir -p "$STORY_DIR/change-requests"
```

## Step 1 — Stop implementation

Do not continue implementing the affected area until this change request is
reviewed and approved. Document what is stopped:
- Which task is paused
- What specifically cannot continue

## Step 2 — Run impact analysis

**Invoke brainstorming sub-skill:**
- **Claude Code:** Use the `Skill` tool with skill name `superpowers:brainstorming`
- **Kiro:** Read `~/.kiro/skills/brainstorming/SKILL.md` and follow it

Focus on:
- What is the original design vs the new proposed design?
- Which areas are affected (API, DB, permissions, tests, frontend, docs)?
- What is the release risk of this change?
- Does this require a new OpenSpec change-id?

## Step 3 — Decide: amendment to existing OpenSpec OR new change-id

If the change is significant enough to warrant a new OpenSpec change (API
contract changed, DB schema changed, or release scope changed):

```
New change-id: <jira-id-lowercase>-cr-<slug>
e.g. example-100-cr-add-site-filter

Run: /opsx:propose example-100-cr-add-site-filter
```

## Step 4 — Write the change request

Write to `$STORY_DIR/change-requests/<YYYY-MM-DD>-<slug>.md`:

```markdown
---
story: <JIRA-ID>
change_date: <YYYY-MM-DD>
slug: <slug>
severity: major
new_openspec_change: <change-id> | none
approved_by: <PM / tech lead — TBD if not yet reviewed>
---

# Change Request: <JIRA-ID> — <slug>

## Change
<what changed and why — discovered during implementation>

## Original Design
<what the approved OpenSpec said>

## New Design
<what it needs to be>

## Impact Analysis

### Areas Affected
| Area | Impact | Action required |
|---|---|---|
| API contract | <changed/unchanged> | Update apidog/contract.md |
| DB schema | <changed/unchanged> | New migration |
| Permission model | <changed/unchanged> | Update proposal |
| Acceptance criteria | <changed/unchanged> | Update specs/ |
| Tests | <changed/unchanged> | Run /testing-regression |
| Frontend | <changed/unchanged> | Notify frontend team |
| Release risk | low/medium/high | <mitigation> |

### Paused Work
- Task: <which task is stopped>
- Reason: <what cannot continue until this CR is approved>

## Decision Log

**Date:** <YYYY-MM-DD>
**Change:** <one sentence>
**Reason:** <why this change was necessary>
**Impact:** <summary of impact>
**Decision:** <what was decided>
**Approved by:** <PM / tech lead — TBD>

## New OpenSpec Change
<change-id or "none — amendment to existing proposal">
Run: /opsx:propose <change-id>   ← only if new change-id is needed

## Next Steps
- [ ] Get CR approved by PM / tech lead / QA
- [ ] Update OpenSpec proposal (or create new change)
- [ ] Regenerate Jira sub-tasks if scope changed
- [ ] Update apidog/contract.md
- [ ] Update test plan
- [ ] Resume implementation
```
