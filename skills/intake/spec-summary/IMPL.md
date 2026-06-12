---
subcommand: spec-summary
group: intake
slash: /intake-spec-summary <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/intake-summary.md
---

# intake/spec-summary — Spec Intake Summarizer

Combines `story.md` + `confluence-*.md` + `apidog-*.md` into a single
`intake-summary.md` that: (a) condenses what the story actually requires,
(b) surfaces what is unclear, (c) records OpenSpec change-ids in frontmatter
so every downstream skill can read them with `resolve_story_dir`.

Corresponds to workflow spec §14.1, skill 3 (spec-intake-summarizer).

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
[[ -f "$STORY_DIR/story.md" ]] || { echo "ERROR: run /intake-jira-story $1 first" >&2; exit 1; }
```

## Step 1 — Read all intake artifacts

Read in this order:
1. `$STORY_DIR/story.md` — Jira title, description, acceptance criteria, status
2. All `$STORY_DIR/confluence-*.md` — referenced Confluence specs
3. All `$STORY_DIR/apidog-*.md` — Apidog or other public API references

## Step 2 — Derive the intake summary

Extract and consolidate:

**Confirmed requirements** — behaviors explicitly stated in both Jira and
at least one Confluence/Apidog page.

**Unclear requirements** — behaviors stated in only one source, or stated
in conflicting ways across sources.

**Assumptions** — things that are implied but not explicitly stated.

**Stakeholders** — who owns / approves / needs to review this story
(PM, tech lead, QA, frontend, backend, etc.).

**Affected product area** — which modules, APIs, or surfaces this touches
(derived from story description + Confluence content).

**Suggested next action** — based on what is present/missing:
- All sources agree and are complete → "Ready for `/audit-spec`"
- Confluence page missing or stubs only → "Get Confluence spec from PM before auditing"
- Apidog reference missing for an API feature → "Confirm API shape before auditing"

## Step 3 — Record OpenSpec change-ids

If the story already has associated OpenSpec changes (because this summary
is being updated mid-flight), preserve the existing `openspec_changes` list.
On first run, initialize it as empty — `audit/handoff` will populate it when
it derives the initial change-id.

## Output format

Write to `$STORY_DIR/intake-summary.md`:

```markdown
---
jira_story: <JIRA-ID>
story_title: <title from story.md>
created_at: <YYYY-MM-DD>
updated_at: <YYYY-MM-DD>
openspec_changes: []
status: intake
---

# Intake Summary: <JIRA-ID>

## Confirmed Requirements
- <requirement 1> *(Jira + confluence-<slug>.md)*
- <requirement 2> *(Jira + apidog-<slug>.md)*

## Unclear Requirements
- <unclear item 1>
  - *Source A says:* ...
  - *Source B says:* ...
  - *Question for:* PM / tech lead

## Assumptions
- <assumption 1> — *If wrong:* <impact>

## Stakeholders
| Role | Name / Team | Needed for |
|---|---|---|
| PM | <from Jira owner/reporter> | Acceptance |
| Backend lead | <from Jira> | Technical review |
| QA | | Test plan approval |

## Affected Product Area
- <module or feature area> — <why affected>

## Source Coverage
| Source | File | Key content |
|---|---|---|
| Jira | story.md | Description, ACs, links |
| Confluence | confluence-<slug>.md | <page title> |
| Apidog | apidog-<slug>.md | <doc title> |

## Suggested Next Action
<ready for /audit-spec | get Confluence spec from PM | ...>

Run: `/audit-spec <JIRA-ID>`
```

## Updating intake-summary.md

After `audit/handoff` runs, it updates the `openspec_changes` list with the
first change-id. After a change request, it adds the CR change-id. This file
is append-friendly — update the frontmatter list without removing past entries.

To update mid-flow:
```bash
# Re-run with --update flag to refresh the summary without overwriting
# the openspec_changes list
/intake-spec-summary <STORY-ID> --update
```

When `--update` is passed, re-read all sources and update all sections
except the `openspec_changes` frontmatter list (preserve existing entries).

### Resolving unclear requirements mid-flow

When an unclear requirement is resolved during the session (e.g. via code
inspection, stakeholder clarification, or reading linked tickets), do NOT
delete the entry. Instead, mark it resolved with strikethrough and a note
so the audit trail is preserved:

```markdown
## Unclear Requirements

- ~~**item title**~~ — **RESOLVED by code inspection**: `path/to/file.go:NN`
  shows that X already does Y. No action needed — the new flow continues
  this behavior per spec.
```

The `~~strikethrough~~` signals the item was considered and closed.
The **RESOLVED** note explains HOW it was resolved and where to verify.
This is better than deletion because `/audit-spec` and future readers can
see the question was asked and answered, not silently ignored.

## Common mistakes

| Mistake | Fix |
|---|---|
| Creating intake-summary.md manually | Run /intake-spec-summary — manual frontmatter errors break resolve_story_dir and downstream skills |
| Treating unclear requirements as confirmed | Mark them unclear; /audit-spec will classify them as must-resolve or can-assume |
| Deleting a resolved unclear requirement | Use strikethrough + **RESOLVED** note instead — preserves the audit trail |
| Leaving openspec_changes empty after /audit-handoff | audit/handoff prints the change-id; update intake-summary.md frontmatter before running /jira-subtasks |
