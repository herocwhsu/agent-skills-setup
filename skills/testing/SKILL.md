---
name: testing
description: Use after the API contract is approved to generate test plans, scaffold RED tests in the test repo, generate regression tests, and verify coverage. Tests should be planned before implementation starts. Four subcommands: plan, write, regression, qa-check.
---

# testing

Plans the test strategy before implementation starts. Workflow spec §4.7:
"Testing should be planned before implementation."

## Subcommands

| Slash command | What it does | Output |
|---|---|---|
| `/testing-plan <STORY-ID>` | Generate test plan from OpenSpec acceptance criteria + Apidog contract. Covers unit, integration, API, regression, and manual QA. | `./docs/stories/<ID>-<slug>/test-plan.md` |
| `/testing-write <STORY-ID>` | For each PR group in `pr-plan.md`, create a `U<n>` companion sub-task in the test repo's Jira project and scaffold RED test stubs in that repo. Impl PR turns them GREEN. | Jira `U<n>` ticket(s) + test files in test repo + updated `pr-plan.md` |
| `/testing-regression <STORY-ID>` | Generate regression tests for a bug fix or change request. Triggered from `change-requests/` or `release/bugfix/`. | `./docs/stories/<ID>-<slug>/regression-tests.md` |
| `/testing-qa-check <STORY-ID>` | Verify test coverage before verification gate. Checks every acceptance criterion, API error, and permission rule has a corresponding test. | stdout only |

## When to use which subcommand

```
Before implementation, spec approved, contract approved   → /testing-plan
After /jira-subtasks confirms pr-plan.md                  → /testing-write
Bugfix or change request created                          → /testing-regression
About to call verification complete                       → /testing-qa-check
```

## Gate rule (workflow spec §16, Rule 4)

```
API contract approved → /testing-plan → /jira-subtasks → /testing-write → Implementation starts
```

Never start implementation on an API feature before `/testing-plan` has run.
Never open a flow PR before its companion `U<n>` test PR exists in RED.
The test plan becomes part of the verification gate at PR time.

## Prerequisites

- `./openspec/changes/<change-id>/specs/` — acceptance scenarios from OpenSpec
- `./docs/stories/<ID>-<slug>/apidog/contract.md` — for API test plan (if API feature)
- `./docs/stories/<ID>-<slug>/story.md` — minimum required
- `./docs/stories/<ID>-<slug>/pr-plan.md` — required for `/testing-write` (created by `/jira-subtasks`)
