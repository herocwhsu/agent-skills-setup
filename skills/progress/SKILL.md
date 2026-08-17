---
name: progress
description: Use to check which spec-gated workflow gates a story has passed and what to run next. Read-only — derives status entirely from artifact files already produced by other skills (story.md, audit-report.md, apidog/contract.md, test-plan.md, etc.), never a separate hand-maintained tracker. One subcommand: status.
---

# progress

Answers "where is this story in the spec-gated workflow, and what's next"
without requiring any other skill to change how it writes its output.

## Subcommands

| Slash command | What it does | Implementation |
|---|---|---|
| `/progress-status <STORY-ID>` | Scan every gate's known output path for this story, print a checklist, and suggest the next command to run. | `status/IMPL.md` |

## When to use

```
Picking up a story after a break, unsure what's already done  → /progress-status
Handing a story off to another agent/session                  → /progress-status
Before running the next gate, to confirm prerequisites exist   → /progress-status
```

## Design note

This does **not** introduce a hand-written progress file. A manually updated
tracker drifts from reality the moment someone forgets to update it after
running a gate. Instead, `status` re-derives state every time by checking for
the artifact files each gate already produces (per that gate's own SKILL.md).
Zero other skill needs to change to support this — `progress` only reads.

The tradeoff: gates that are stdout-only (`audit-handoff`, `testing-qa-check`,
`jira-evidence`) can't be directly detected. `status` infers those from
downstream evidence instead (see `status/IMPL.md`) and marks them
"probably ran" rather than claiming certainty.
