---
name: repo
description: Use before writing an OpenSpec proposal to understand what the target codebase actually looks like. Subcommand context-scan identifies affected modules, existing APIs, DTOs, DB tables, test patterns, and known limitations. Third gate of the spec-gated workflow.
---

# repo

Reads the target repository to ground the OpenSpec proposal in real code,
not assumptions. Agents that skip this gate write specs that don't match the
codebase.

## Subcommands

| Slash command | What it does | Output |
|---|---|---|
| `/repo-context-scan <STORY-ID>` | Scan affected modules, APIs, DTOs, DB schema, test coverage, and coding conventions. Uses `gh` CLI + `grep` + `find`. | `./docs/stories/<ID>-<slug>/repo-context.md` |
| `/repo-domain-notes query <keyword>` | Search the repo's persistent knowledge cache before doing git archaeology or code reading. | reads `./.spec-gated/domain-notes.md` |
| `/repo-domain-notes add` | Append a fact learned during this story's investigation (removed module, permission-check chain, migration history, naming quirk) so the next story doesn't re-discover it. | `./.spec-gated/domain-notes.md` |

## Prerequisites

- `gh` CLI authenticated (`gh auth status` succeeds)
- `cwd` is inside the target repo
- `story.md` exists (run `/intake-jira-story` first)

## When to use

Run after `/audit-spec` and before `/audit-handoff`:

```
/audit-spec <STORY-ID>
/repo-domain-notes query <keyword>   ← check cache before digging, cheap
/repo-context-scan <STORY-ID>
/audit-domain-risk <STORY-ID>
/repo-domain-notes add               ← write down anything non-obvious learned
/audit-handoff <STORY-ID>            ← reads repo-context.md if present
```

`domain-notes` is cross-story and persistent (one file per repo, under
`./.spec-gated/`); `context-scan` is per-story and thrown away once the story
ships. Query the cache first — it's a shortcut, not a replacement for the
scan.

`/audit-handoff` includes `repo-context.md` content in the context it passes
to `/opsx:propose`. The OpenSpec design section should reference the affected
modules and existing patterns found here.
