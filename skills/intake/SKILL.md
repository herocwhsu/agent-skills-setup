---
name: intake
description: Use to bring outside specs into a story folder under ./docs/stories/<JIRA-ID>-<slug>/. Subcommands fetch a Jira story (jira-story), fetch a web page or Confluence page as markdown reference (web-page), and produce an intake summary that ties Jira + Confluence + Apidog into a single brief (spec-summary). First gate of the spec-gated workflow.
---

# intake

Pulls Jira stories, Confluence pages, and other reference URLs into a single
per-story folder. Produces the upstream evidence later gates depend on.

## Subcommands

| Slash command | What it does | Implementation |
|---|---|---|
| `/intake-jira-story <STORY-ID>` | Fetch a Jira issue + every embedded link, write `./docs/stories/<STORY-ID>-<slug>/story.md` plus one `confluence-*.md` / `apidog-*.md` per link. | `jira-story/IMPL.md` |
| `/intake-web-page <URL>` | Fetch one URL, save as dated markdown reference. Confluence URLs go through the REST API path; everything else uses plain curl. | `web-page/IMPL.md` |
| `/intake-spec-summary <STORY-ID>` | Combine `story.md` + `confluence-*.md` + `apidog-*.md` into `intake-summary.md` with frontmatter listing `jira_story` and `openspec_changes`. | `spec-summary/IMPL.md` |

## When to use which subcommand

```
User mentions a Jira ID (PROJ-123, BUG-2034) → /intake-jira-story
User pastes a single URL with no Jira context → /intake-web-page
User asks "what does this story actually need?" or "summarize this intake" → /intake-spec-summary
```

`/intake-jira-story` already calls `web-page` internally for each Confluence /
Apidog link found in the Jira description, so you rarely need to run
`web-page` directly when you have a Jira ticket.

## Output convention

All artifacts land under one folder per story:

```
./docs/stories/<JIRA-ID>-<slug>/
  story.md
  confluence-<slug>.md
  apidog-<slug>.md
  intake-summary.md          # spec-summary writes this
```

`<slug>` is derived from the Jira issue summary by `intake-jira-story`. If the
folder doesn't yet exist when a downstream skill runs, the user is expected to
have run `/intake-jira-story <STORY-ID>` first.

## How to run a subcommand

Each subcommand has its own `IMPL.md` next to this file:

```
skills/intake/
  SKILL.md             # this file (router)
  jira-story/IMPL.md   # /intake-jira-story implementation
  web-page/IMPL.md     # /intake-web-page implementation
```

When invoked, read the matching `IMPL.md` for the full bash recipe, credential
checks, and error handling. Implementations have not changed from the
pre-refactor `fetch-jira-story` and `fetch-page-to-markdown` skills — only
their location has.

## Credentials

Both subcommands use `~/.agent-skills-setup/lib.sh` helpers (`load_config`,
`require_secret`, `service_slug`). Jira and Confluence credentials live in the
platform keychain under `agent-skills-setup:jira` and
`agent-skills-setup:confluence`. Set them up with:

```bash
bash scripts/credentials/service.sh jira add
bash scripts/credentials/service.sh confluence add
```

Verify (no value printed):

```bash
bash scripts/credentials/service.sh jira verify
bash scripts/credentials/service.sh confluence verify
```

## Migration note (from pre-refactor layout)

| Old skill | New subcommand | Old slash | New slash |
|---|---|---|---|
| `fetch-jira-story` | `intake/jira-story` | `/fetch-jira-story` | `/intake-jira-story` |
| `fetch-page-to-markdown` | `intake/web-page` | `/fetch-page-to-markdown` | `/intake-web-page` |

Same scripts, same credentials, same outputs. Only the wrapper SKILL.md and
slash command changed.
