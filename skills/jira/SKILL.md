---
name: jira
description: Use to create or close Jira artifacts that anchor the spec-gated workflow. Subcommands generate sub-tasks from a confirmed plan/proposal (subtasks) and verify evidence links before closure (evidence). Reads from ./docs/stories/<JIRA-ID>-<slug>/ and the OpenSpec change folder.
---

# jira

Connects approved specs to Jira tickets and verifies the evidence trail.

## Subcommands

| Slash command | What it does | Implementation |
|---|---|---|
| `/jira-subtasks <STORY-ID>` | Read the OpenSpec `tasks.md` (or pre-OpenSpec `plan.md` during transition) for a story, create one Jira sub-task per task, write the sub-task IDs back into the source file. | `subtasks/IMPL.md` |
| `/jira-evidence <STORY-ID>` | Walk every sub-task on a Jira story and check that each has the required evidence links (PR, Apidog, CI, OpenSpec change). Stdout report only; no file output. | Phase 2 (not yet built) |

## When to use which subcommand

```
Story has an approved spec (OpenSpec change) and tasks ready → /jira-subtasks
Story is about to close, want to confirm "no evidence, no closure" → /jira-evidence
```

## Source of tasks

`/jira-subtasks` reads from these locations in order, using the first one
that exists:

1. `./openspec/changes/<change-id>/tasks.md` — the canonical post-OpenSpec source
2. `./docs/stories/<JIRA-ID>-<slug>/plan.md` — legacy fallback for stories
   that were planned before OpenSpec was in the loop

The `<change-id>` is read from the `openspec_changes` frontmatter list in
`./docs/stories/<JIRA-ID>-<slug>/intake-summary.md` (Phase 2). For Phase 1,
`/jira-subtasks` keeps reading the legacy `plan.md` to preserve current
behavior.

## Credentials

`agent-skills-setup:jira` keychain entry plus `JIRA_HOST`, `JIRA_USER`,
`JIRA_PROJECT_KEY` in `~/.agent-skills-setup/config.sh`. Set up with:

```bash
bash scripts/credentials/service.sh jira add
```

## Migration note

| Old skill | New subcommand | Old slash | New slash |
|---|---|---|---|
| `create-story-tasks` | `jira/subtasks` | `/create-story-tasks` | `/jira-subtasks` |

Same script, same credentials, same outputs. `/jira-evidence` is new in Phase 2.
