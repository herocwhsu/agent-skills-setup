---
name: audit
description: Use after intake is complete to audit the spec before OpenSpec proposal. Subcommands check for spec conflicts/gaps (spec), flag domain-specific risks (domain-risk), and assemble all upstream evidence then hand off to /opsx:propose (handoff). Second and third gates of the spec-gated workflow.
---

# audit

Validates the raw spec before the OpenSpec proposal is written.
No implementation happens until this group's gates pass.

## Subcommands

| Slash command | What it does | Output |
|---|---|---|
| `/audit-spec <STORY-ID>` | Audit the intake artifacts for conflicts, gaps, missing behaviors. Merged spec-audit + gap-detector (always co-triggered, same input). | `./docs/stories/<ID>-<slug>/audit-report.md` |
| `/audit-domain-risk <STORY-ID>` | Check for domain-specific risks (permissions, tenant isolation, error handling, etc.) against a generic or repo-customized checklist. | `./docs/stories/<ID>-<slug>/domain-risk.md` |
| `/audit-handoff <STORY-ID>` | Assemble all upstream evidence, invoke brainstorming, then print the recommended `/opsx:propose <change-id>` invocation. This is the gate to OpenSpec. | stdout only |

## When to use which subcommand

```
Intake complete, want to find spec holes before writing a proposal → /audit-spec
Want to flag camera/permission/tenant/retention risks specific to this domain → /audit-domain-risk
Ready to move from intake/audit to OpenSpec proposal → /audit-handoff
```

Run all three in order:
```
/audit-spec <STORY-ID>
/audit-domain-risk <STORY-ID>
/audit-handoff <STORY-ID>
```

`handoff` reads the output of `spec` and `domain-risk` if they exist, so run
them first. `handoff` does NOT require them — it will note which artifacts are
missing and suggest running them before proceeding.

## Gate rule

No `/opsx:propose` without `audit-handoff`. No `audit-handoff` without a
reviewed `audit-report.md`. This is the spec-gated workflow's enforcement
point between "Confluence rough spec → implementation".

## Prerequisites

- `./docs/stories/<STORY-ID>-<slug>/story.md` must exist (`/intake-jira-story` first)
- `resolve_story_dir` from `~/.agent-skills-setup/lib.sh` resolves the folder

## Domain risk customization

Create `./.spec-gated/domain-risk-checks.md` in the target repo to override
or extend the built-in generic check list. If this file exists, its checks
replace the defaults. The generic fallback covers:

- Tenant isolation
- Permission/authorization model
- Error behavior (400/401/403/404/429/5xx)
- Data retention / deletion
- Audit log
- Notification behavior
- Latency / bandwidth
- Failover / offline behavior
