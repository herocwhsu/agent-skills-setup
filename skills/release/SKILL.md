---
name: release
description: Use for the final gates of the spec-gated workflow. Subcommands check release readiness (readiness), classify post-release issues (triage), generate bugfix specs (bugfix-spec), and verify the spec archive is complete (archive-check). Last gates before and after production.
---

# release

Guards the release and handles what comes after it.

## Subcommands

| Slash command | What it does | Output |
|---|---|---|
| `/release-readiness <STORY-ID>` | Check that all gates have passed before releasing: OpenSpec applied, Jira complete, Apidog updated, tests passed, monitoring ready. | `./docs/stories/<ID>-<slug>/release/readiness.md` |
| `/release-triage <STORY-ID> <description>` | Classify a post-release issue (incident, bug, regression, spec-gap, enhancement, operational). Merged: post-release-triage + follow-up-proposal-generator. | `./docs/stories/<ID>-<slug>/release/triage.md` |
| `/release-bugfix-spec <STORY-ID> <BUG-ID>` | Convert a production bug into a structured bugfix spec with regression test plan. | `./docs/stories/<ID>-<slug>/release/bugfix/<BUG-ID>-<slug>/bugfix-spec.md` |
| `/release-archive-check <STORY-ID>` | Verify the final spec archive is complete — every OpenSpec change-id archived, all evidence links present. Phase 3. | `./docs/stories/<ID>-<slug>/archive.md` |

## When to use which subcommand

```
About to merge final PR / tag release → /release-readiness
Post-release issue reported → /release-triage
Triage says "bug" → /release-bugfix-spec <ORIGINAL-STORY-ID> <BUG-JIRA-ID>
Story confirmed done, archiving → /release-archive-check
```

## Hard rules (workflow spec §12 + §16)

```
Rule: No evidence, no closure.
Rule: No regression test, no bugfix closure.
Rule: Post-release issues must be triaged before reopening the original story.
```

## Post-release triage categories (workflow spec §12.1)

| Type | Definition | Process |
|---|---|---|
| Incident | System stability, security, data correctness, severe impact | Incident + hotfix (out of band) |
| Bug | Released behavior does not match approved spec | `/release-bugfix-spec` |
| Regression | Previously working behavior broken | `/release-bugfix-spec` + `/testing-regression` |
| Spec gap | Original spec was unclear/incomplete | Clarification + new proposal |
| Enhancement | New requirement or improvement | New OpenSpec proposal via `/opsx:propose` |
| Operational | Deployment, monitoring, config, data | Ops/infra ticket |
