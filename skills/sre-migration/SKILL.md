---
name: sre-migration
description: Use when an SRE data-migration or data-patching request needs a tool and a Migration Execution ticket. Subcommands scaffold a six-operation correction tool with one input sample per environment (scaffold), draft the ticket body and per-environment command flow (draft), gate that draft against the checks that got past tickets bounced (lint), and file the SRE issue (ticket). Run them in that order; lint before ticket is the point of the skill.
---

# sre-migration

Turns an SRE correction request into the artifacts its ticket template demands:
a conforming tool, per-environment inputs, a ticket body, an execution command
flow, and a lint pass before anything is filed.

Named for the Jira work type `Change Request - Migration Execution`. Not for
`db_schema/` schema migrations, and not for OpenSpec "Migration note" sections.

## Subcommands

| Slash command | What it does | Output | Implementation |
|---|---|---|---|
| `/sre-migration-scaffold <name>` | Generate a six-operation tool skeleton plus one input sample per environment the tool accepts | `extend/scripts/<name>/` | `scaffold/IMPL.md` |
| `/sre-migration-draft <STORY-ID>` | Read the ticket template, draft the ticket body and the per-environment command flow (Chinese) | `./docs/stories/<STORY-ID>-<slug>/migration-ticket.md`, `command-flow.md` | `draft/IMPL.md` |
| `/sre-migration-lint <STORY-ID>` | Run the 12 checks against the draft; report the high-risk criteria's inputs | stdout report | `lint/IMPL.md` |
| `/sre-migration-ticket <STORY-ID>` | File the SRE issue from the linted draft | Jira issue key | `ticket/IMPL.md` |

## When to use which subcommand

```
New correction needed, no tool exists yet    → /sre-migration-scaffold
Reusing an existing tool for a new ticket    → skip scaffold, add templates/<jira-id>/ samples
Tool ready, dev precheck output captured     → /sre-migration-draft
Draft written, before filing anything        → /sre-migration-lint   (fix, re-run until clean)
Lint clean, high-risk call made by a human   → /sre-migration-ticket
```

## What this skill does not decide

- **Whether a change is high risk.** `lint` reports the five criteria's inputs
  — affected rows against both thresholds, PII category, estimated downtime,
  service/database count, rollback presence. A human concludes, because the
  consequence is a management sign-off and a low-traffic window.
- **Anything on stage or prod.** Those runs are handed to SRE as prepared
  commands. Only dev is run directly.
- **SRE's three record fields.** `SRE Pre-check`, `SRE Stage Record`, and
  `SRE Prod Record` are separate Jira custom fields, left empty for SRE — not
  sections of the ticket body.

## Conventions this skill enforces

- **Six operations**: `precheck`, `backup`, `migrate`, `verify`, `rollback`,
  `restore`. `restore` is a whole-restore from the backup; `rollback` is the
  logical inverse. Each declares 是否提供 / 說明 / 可否重複執行.
- **Coverage is the deployed trio** — dev, stage, prod. Not `local` (it
  resolves to `http://localhost:8080`, a developer's own machine), and a missing
  env is acceptable when `NOTES.md` explains the absence.
- **Fail closed**: generated `migrate`/`rollback`/`restore` change nothing
  without `--apply`, and refuse an unbounded `UPDATE`/`DELETE`.
- **`NOTES.md` per ticket directory**, carrying the target reasoning.
- Sample filenames are env-prefixed: `<env>-<target>-<action>.json`.

## Credentials

Uses the `jira` entry via `load_config` → `service_slug` → `require_secret`,
with the secret unset immediately and never printed. Needs `JIRA_HOST` and
`JIRA_USER` in `~/.agent-skills-setup/config.sh`:

```bash
bash scripts/credentials/service.sh jira add
```

The ticket template is Cloud-hosted under the Jira site host at `/wiki`, so it
answers to that same credential — not to `CONFLUENCE_HOST`, which is
self-hosted and resolves only on the corporate network.
