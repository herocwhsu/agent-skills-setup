---
name: spec-workflow
description: Use before writing implementation code for production-bound feature work, or for any change to external contracts, API behavior, permissions, data models, data correctness, security, migrations, or user-visible behavior. Defines the gate order (intake → audit → repo → external → testing → jira → release), the OpenSpec addendum, and how mid-implementation spec changes are handled. Exploratory spikes, investigations, refactors, tests, and docs-only work are exempt unless they change one of those.
---

# spec-workflow

The production gate sequence. Moved out of the global engineering rules so it
loads only for production work; the global file keeps a one-line trigger.
Each gate is its own skill; this file is the order and the rules between them.

## Production Spec-Gated Workflow

*   **Directive:** Before writing implementation code for a new production feature or significant production behavior change, the following gates should pass in order when applicable. Every artifact lives under `./docs/stories/<JIRA-ID>-<slug>/`, so this flow needs no OpenSpec:

    1. **Intake** — fetch the Jira story and Confluence specs (`intake`)
    2. **Audit** — spec audit plus domain risk check (`audit`)
    3. **Repo context scan** — inspect the affected code, tests, callers, and conventions (`repo`)
    4. **External dependency handling** — only if the story has an unresolved third-party/vendor dependency; document known vs unknown, generate a provisional contract, plan a mock provider so unrelated tasks aren't blocked (`external`)
    5. **Test plan** — define the test strategy before implementation (`testing`)
    6. **Jira sub-tasks + evidence** — create sub-tasks from the confirmed plan; before closing the story, verify every sub-task has the required evidence links (PR, CI, contract) — no evidence, no closure (`jira`)
    7. **Release gate** — before closing the story, check release readiness (`release readiness`); after merge, verify the spec archive is complete (`release archive-check`, alongside `/opsx:archive` where OpenSpec applies); post-release issues go through `release triage`, which can produce a `release bugfix-spec` to restart the loop (`release`)

*   **Process layer:** use the superpowers skills for the thinking steps rather than improvising them — brainstorming before design, `test-driven-development` while implementing, `verification-before-completion` before any claim that work is done. Gate 2's `audit-handoff` already invokes brainstorming.
*   To check where a story currently stands in this list without re-deriving it from memory, run `/progress-status <STORY-ID>` — it reads the artifact files each gate already produces and reports what's done and what's next.
*   If a gate is unavailable, intentionally skipped, already satisfied, or not applicable, state that explicitly.
*   Mid-implementation spec changes must go through `/review-amend` for small changes or `/review-change-request` for major changes. Never silently change code to match a changed spec.
*   This workflow applies to production-bound feature work.
*   It does **not** block clearly marked exploratory experiments, local spikes, investigation, refactors, tests, or documentation-only work unless they change:
    - External contracts
    - API behavior
    - Permissions
    - Data models
    - Data correctness
    - Security behavior
    - Production behavior
    - Migration behavior
    - User-visible behavior
*   Any productionization of an experiment must return to this workflow.

## OpenSpec addendum (only if the repo has an `openspec/` directory)

Some shared repos layer OpenSpec on the flow above. `/opsx:*` is the OpenSpec CLI, not a skill here, so with no `openspec/` directory skip this addendum entirely rather than reporting a blocked gate. Where it applies, add:

*   After gate 2, create or update the proposal via `/opsx:propose <change-id>`. `audit-handoff` prints the invocation rather than running it.
*   **Apidog contract review** for API features (`apidog`) — it prefers the approved proposal as its spec source, and says so in the generated contract when it had to fall back to the story artifacts instead.
*   While a PR is open, diff the implementation against the approved proposal (`review-guardrails`) to catch missing requirements, extra behavior, or risky changes before merge.
*   After merge, run `/opsx:archive <change-name>` — it promotes the delta into `openspec/specs/` and archives the change folder. Skipping it leaves canonical specs out of sync with shipped code.
