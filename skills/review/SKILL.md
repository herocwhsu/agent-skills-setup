---
name: review
description: Use for code-review and spec-vs-implementation quality gates. Subcommands mine recurring review patterns from a repo's PR history (mine-patterns), review a single PR against the playbook (pr), diff implementation against the approved OpenSpec proposal (guardrails), and capture mid-implementation amendments or change requests (amend, change-request).
---

# review

Quality gates that surround implementation: code review, spec compliance, and
governance for mid-implementation deviations.

## Subcommands

| Slash command | What it does | Implementation |
|---|---|---|
| `/review-mine-patterns [count]` | Scan recent closed PRs in the current repo, distill recurring review themes into `./.code-review/playbook.md`. Default scan: 50 PRs. | `mine-patterns/IMPL.md` |
| `/review-pr <number>` | Review one PR using the mined playbook. Produces a local report plus a 3-5 issue comment draft (manual-post). | `pr/IMPL.md` |
| `/review-guardrails <STORY-ID>` | Diff a PR against the approved `./openspec/changes/<change-id>/proposal.md`. Reports missing requirements, extra behavior, risky changes. Stdout only. | Phase 2 (not yet built) |
| `/review-amend <STORY-ID> <slug>` | Capture a small spec amendment as `./docs/stories/<JIRA-ID>-<slug>/amendments/<date>-<slug>.md`. For wording, field, or edge-case clarifications. | Phase 2 (not yet built) |
| `/review-change-request <STORY-ID> <slug>` | Capture a major change request as `./docs/stories/<JIRA-ID>-<slug>/change-requests/<date>-<slug>.md`. Includes impact analysis + decision log. May spawn a new OpenSpec change-id (`<jira-id>-cr-<slug>`). | Phase 2 (not yet built) |

## When to use which subcommand

```
First time reviewing in this repo this quarter → /review-mine-patterns
Reviewing one specific PR → /review-pr <num>
PR is open and you want to compare it to the approved spec → /review-guardrails
During implementation, the spec has a small wording bug → /review-amend
During implementation, the API contract or scope changed → /review-change-request
```

## Amendment vs change-request rule (workflow doc §10.3)

| Question | Amendment | Change Request |
|---|---|---|
| Only wording or small clarification? | ✓ | |
| API contract affected? | | ✓ |
| Database schema affected? | | ✓ |
| Permission or security affected? | | ✓ |
| Release scope affected? | | ✓ |
| Test baseline changed? | maybe | usually ✓ |

If unsure, treat it as a change request — it costs more process but loses no
information. Amendments are append-only: never edit a previous amendment, add
a new one.

## Migration note

| Old skill | New subcommand | Old slash | New slash |
|---|---|---|---|
| `mine-review-patterns` | `review/mine-patterns` | `/mine-review-patterns` | `/review-mine-patterns` |
| `review-pr` | `review/pr` | `/review-pr` | `/review-pr` (path same, source moves) |

`mine-patterns/charter.md` and `pr/charter.md` retain their existing roles —
the long-form rationale each script consults at runtime.

`./.code-review/playbook.md` location is unchanged. Repos that already have a
mined playbook keep working without re-mining.
