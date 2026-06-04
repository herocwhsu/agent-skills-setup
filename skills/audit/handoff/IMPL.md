---
subcommand: handoff
group: audit
slash: /audit-handoff <STORY-ID>
output: stdout only (prints /opsx:propose instruction with assembled context)
---

# audit/handoff — Audit Gate to OpenSpec

Assembles all upstream evidence for a story, invokes `superpowers:brainstorming`
to surface any remaining unknowns, then prints the recommended
`/opsx:propose <change-id>` invocation with pre-assembled context.

This is the gate between "Confluence rough spec + audit" and "OpenSpec
proposal". Do not invoke `/opsx:propose` without running this handoff first.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

## Step 1 — Verify upstream gates

Check which artifacts exist in the story folder:

| Artifact | Required | Status |
|---|---|---|
| `story.md` | Yes — abort if missing | |
| `confluence-*.md` | Recommended — warn if zero | |
| `audit-report.md` | Recommended — warn if missing | |
| `domain-risk.md` | Recommended — warn if missing | |
| `repo-context.md` | Optional (Phase 2: repo/context-scan) | |

If `story.md` is missing, abort with:
```
ERROR: story.md not found in <STORY_DIR>
  Run: /intake-jira-story <STORY-ID> first
```

If `audit-report.md` is missing, print a warning and continue:
```
WARNING: audit-report.md not found — run /audit-spec <STORY-ID> before
  creating the OpenSpec proposal. Continuing with available artifacts.
```

If `audit-report.md` has `status: needs-work`, print a warning:
```
WARNING: audit-report.md has status: needs-work (must-resolve gaps open).
  Resolve gaps before proceeding. Continuing anyway — your call.
```

## Step 2 — Read all artifacts

Read every file in `$STORY_DIR/`:
- `story.md`
- `confluence-*.md` (all, in alphabetical order)
- `apidog-*.md` (all)
- `audit-report.md` (if exists)
- `domain-risk.md` (if exists)
- `repo-context.md` (if exists)

## Step 3 — Invoke brainstorming

**Invoke brainstorming sub-skill:**
- **Claude Code:** Use the `Skill` tool with skill name `superpowers:brainstorming`
- **Kiro:** Read `~/.kiro/skills/brainstorming/SKILL.md` and follow it

Focus brainstorming on:
- What is the core problem this story solves?
- What design options exist? What are the trade-offs?
- What are the highest-risk unknowns still open after audit?
- What external dependencies could block or shape the design?
- What acceptance criteria are missing or untestable?

Capture brainstorming output in memory — it feeds the next step.

## Step 4 — Derive the OpenSpec change-id

Construct the change-id from the Jira story ID and a slug derived from the
story title:

```bash
JIRA_ID="$1"                          # e.g. EXAMPLE-100
SUMMARY=$(grep "^# " "$STORY_DIR/story.md" | head -1 | sed 's/^# [A-Z0-9-]*: //')
SLUG=$(story_slug_from_summary "$SUMMARY" | cut -c1-40)
CHANGE_ID="${JIRA_ID,,}-${SLUG}"      # e.g. example-100-add-camera-group-filter
```

Print the derived change-id for the user to confirm or override.

## Step 5 — Print the /opsx:propose invocation

Print a ready-to-run block that the user (or orchestrating agent) can execute:

```
============================================================
AUDIT HANDOFF: <JIRA-ID>
============================================================

Upstream evidence assembled:
  ✓ story.md
  ✓ confluence-<n> pages
  ⚠ audit-report.md missing (recommended)
  ...

Brainstorming complete. Key findings:
  - <finding 1>
  - <finding 2>
  - <finding 3>

Proposed OpenSpec change-id:
  <CHANGE-ID>
  (e.g. example-100-add-camera-group-filter)

Next step — run this in your target repo:

  /opsx:propose <CHANGE-ID>

Then paste this context into the proposal prompt:

--- CONTEXT START ---
Story: <JIRA-ID> — <title>

Problem:
<derived from story.md>

Goals:
<derived from acceptance criteria and audit>

Key risks (from domain-risk.md):
<list of flagged risks>

Must-resolve gaps (from audit-report.md):
<list of must-resolve items — empty if none>

Brainstorming findings:
<key findings from step 3>
--- CONTEXT END ---

After /opsx:propose creates the spec files, run:
  /jira-subtasks <JIRA-ID>       — generate Jira sub-tasks from tasks.md
  /apidog-contract <JIRA-ID>     — plan API contracts (if API feature)
  /testing-plan <JIRA-ID>        — generate test plan

============================================================
```

## What NOT to do

- Do not call `/opsx:propose` yourself. Print the instruction; the user runs it.
- Do not write anything to `./openspec/`. OpenSpec owns that tree.
- Do not skip brainstorming even if artifacts look complete — it surfaces
  design options the spec may not have considered.

## Common mistakes

| Mistake | Fix |
|---|---|
| Skipping this handoff and calling /opsx:propose directly | Always run audit-handoff — it enforces the spec-gated workflow |
| Treating a warning about missing audit-report as an error | Warn and continue; the user may have a good reason to skip |
| Copying the full audit-report into the context | Summarize: list only must-resolve gaps and flagged risks |
