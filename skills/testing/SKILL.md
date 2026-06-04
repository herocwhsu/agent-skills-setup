---
name: testing
description: Use after the API contract is approved to generate test plans, regression tests, and verification checklists. Tests should be planned before implementation starts. Three subcommands: plan, regression, qa-check.
---

# testing

Plans the test strategy before implementation starts. Workflow spec §4.7:
"Testing should be planned before implementation."

## Subcommands

| Slash command | What it does | Output |
|---|---|---|
| `/testing-plan <STORY-ID>` | Generate test plan from OpenSpec acceptance criteria + Apidog contract. Covers unit, integration, API, regression, and manual QA. | `./docs/stories/<ID>-<slug>/test-plan.md` |
| `/testing-regression <STORY-ID>` | Generate regression tests for a bug fix or change request. Triggered from `change-requests/` or `release/bugfix/`. | `./docs/stories/<ID>-<slug>/regression-tests.md` |
| `/testing-qa-check <STORY-ID>` | Verify test coverage before verification gate. Checks every acceptance criterion, API error, and permission rule has a corresponding test. | stdout only |

## When to use which subcommand

```
Before implementation, spec approved, contract approved → /testing-plan
Bugfix or change request created → /testing-regression
About to call verification complete → /testing-qa-check
```

## Gate rule (workflow spec §16, Rule 4)

```
API contract approved → /testing-plan → Implementation starts
```

Never start implementation on an API feature before `/testing-plan` has run.
The test plan becomes part of the verification gate at PR time.

## Prerequisites

- `./openspec/changes/<change-id>/specs/` — acceptance scenarios from OpenSpec
- `./docs/stories/<ID>-<slug>/apidog/contract.md` — for API test plan (if API feature)
- `./docs/stories/<ID>-<slug>/story.md` — minimum required
