# Migration: Flat Skills → Spec-Gated Groups

The 11 individual custom skills have been folded into 11 group skills (5 with
migrated subcommands, 6 new spec-gated groups). Same credentials throughout —
only the slash commands, source paths, and output conventions changed.

Run `bash scripts/install.sh` after pulling to deploy the new layout.

## Slash command mapping

| Old slash | New slash | Notes |
|---|---|---|
| `/fetch-jira-story <ID>` | `/intake-jira-story <ID>` | Now writes to `./docs/stories/<JIRA-ID>-<slug>/` (slug from Jira summary) |
| `/fetch-page-to-markdown <URL>` | `/intake-web-page <URL>` | Same `./docs/pre-specs/` output for ad-hoc fetches; called internally by `/intake-jira-story` for embedded links |
| `/plan-story` | **Retired** — use the spec-gated flow | See [Replacing plan-story](#replacing-plan-story) below |
| `/create-story-tasks <ID>` | `/jira-subtasks <ID>` | Now reads OpenSpec `tasks.md` first, falls back to legacy `plan.md` |
| `/mine-review-patterns [count]` | `/review-mine-patterns [count]` | Output still at `./.code-review/playbook.md` |
| `/review-pr <num>` | `/review-pr <num>` | Path unchanged; source moved to `skills/review/pr/` |
| `/confluence-tree-fetch <id>` | `/utils-confluence-tree-fetch <id>` | Self-hosted Server/DC migration only |
| `/confluence-tree-upload <dir> --parent <id> --space <KEY>` | `/utils-confluence-tree-upload ...` | Same args |
| `/confluence-link-rewrite-preview <dir> --parent <id>` | `/utils-confluence-link-rewrite-preview ...` | Same args |
| `polish-input` (hook, no slash) | `polish-input` (hook, no slash) | Hook path updated to `${AGENT_SKILLS_DIR}/utils/polish-input/lib/polish.py`; re-wire with `bash scripts/install.sh --with-hook polish-input` |
| `/kiro-gateway <sub>` | `/infra-kiro-gateway <sub>` | Subcommands unchanged: `init`, `update`, `rollback`, `status`, `setup-alias` |
| `/host-optimization` | `/infra-host-optimization` | `--revert` flag unchanged |

## New spec-gated slash commands

These did not exist in the old flat layout. All are now available after install.

| Slash command | Group | What it does |
|---|---|---|
| `/intake-spec-summary <ID>` | `intake` | Combines `story.md` + Confluence + Apidog into `intake-summary.md` with `openspec_changes` frontmatter |
| `/audit-spec <ID>` | `audit` | Spec audit + gap detection → `audit-report.md` |
| `/audit-domain-risk <ID>` | `audit` | Domain risk check → `domain-risk.md` |
| `/audit-handoff <ID>` | `audit` | Assembles all upstream evidence, runs brainstorming, prints `/opsx:propose <change-id>` instruction |
| `/repo-context-scan <ID>` | `repo` | Scans target repo (gh, git, ripgrep) → `repo-context.md` |
| `/external-deps <ID>` | `external` | Documents external dep, writes provisional contract + mock plan → `external-deps.md` |
| `/jira-evidence <ID>` | `jira` | Checks all sub-tasks have required evidence links (PR, Apidog, CI, OpenSpec) |
| `/apidog-contract <ID>` | `apidog` | Generates API contract plan → `apidog/contract.md` |
| `/apidog-mocks <ID>` | `apidog` | Generates mock response examples → `apidog/mocks.md` |
| `/apidog-testcases <ID>` | `apidog` | Generates API test cases → `apidog/testcases.md` |
| `/testing-plan <ID>` | `testing` | Test plan from OpenSpec + Apidog → `test-plan.md` |
| `/testing-regression <ID>` | `testing` | Regression tests for bugfix or change request → `regression-tests.md` |
| `/testing-qa-check <ID>` | `testing` | Verifies test coverage before verification gate (stdout) |
| `/review-guardrails <ID> <pr>` | `review` | Diffs PR against approved OpenSpec proposal (stdout) |
| `/review-amend <ID> <slug>` | `review` | Small spec amendment → `amendments/YYYY-MM-DD-<slug>.md` |
| `/review-change-request <ID> <slug>` | `review` | Major change request with impact analysis → `change-requests/YYYY-MM-DD-<slug>.md` |
| `/release-readiness <ID>` | `release` | Checks all gates before release → `release/readiness.md` |
| `/release-triage <ID> "<issue>"` | `release` | Classifies post-release issue → `release/triage.md` |
| `/release-bugfix-spec <ID> <BUG-ID>` | `release` | Bugfix spec + regression plan → `release/bugfix/<BUG-ID>-<slug>/` |
| `/release-archive-check <ID>` | `release` | Verifies all OpenSpec changes archived + evidence complete → `archive.md` |

## Replacing plan-story

`/plan-story` is retired. It produced a `plan.md` before OpenSpec was in the
loop. The spec-gated replacement separates the flow into discrete gates:

```
# Old flow:
/fetch-jira-story PROJ-123
/plan-story           ← produced plan.md
/create-story-tasks   ← created Jira sub-tasks from plan.md

# New flow:
/intake-jira-story PROJ-123         ← Gate 1: fetch story + linked specs
/intake-spec-summary PROJ-123       ← Gate 2: consolidate intake

/audit-spec PROJ-123                ← Gate 3: spec audit
/repo-context-scan PROJ-123         ← Gate 4: repo scan
/audit-domain-risk PROJ-123         ← Gate 5: domain risk
/audit-handoff PROJ-123             ← Gate 6: prints /opsx:propose <change-id>

# User runs:
/opsx:propose <change-id>           ← creates OpenSpec proposal/design/tasks

/jira-subtasks PROJ-123             ← Gate 7: Jira sub-tasks from OpenSpec tasks.md
/apidog-contract PROJ-123           ← Gate 8: API contract (if API feature)
/testing-plan PROJ-123              ← Gate 9: test plan before implementation
```

If you have existing `plan.md` files from the old flow, `/jira-subtasks` still
reads them as a legacy fallback when no OpenSpec `tasks.md` exists.

## Output folder layout

The single per-story root:

```
./docs/stories/<JIRA-ID>-<slug>/
```

Example: `./docs/stories/EXAMPLE-100-add-camera-group-filter/`

Full layout (all files written by spec-gated skills):

```
./docs/stories/EXAMPLE-100-add-camera-group-filter/
  story.md                       intake/jira-story
  confluence-<slug>.md            intake/web-page (one per linked page)
  apidog-<slug>.md                intake/web-page
  intake-summary.md               intake/spec-summary

  audit-report.md                 audit/spec
  domain-risk.md                  audit/domain-risk
  repo-context.md                 repo/context-scan
  external-deps.md                external/deps (when external dep exists)

  apidog/contract.md              apidog/contract
  apidog/mocks.md                 apidog/mocks
  apidog/testcases.md             apidog/testcases

  test-plan.md                    testing/plan
  regression-tests.md             testing/regression (bugfix/change-request only)

  amendments/YYYY-MM-DD-<slug>.md         review/amend
  change-requests/YYYY-MM-DD-<slug>.md    review/change-request

  release/readiness.md            release/readiness
  release/triage.md               release/triage (post-release)
  release/bugfix/<BUG-ID>-<slug>/ release/bugfix-spec
  archive.md                      release/archive-check
```

Pre-refactor stories under `./docs/stories/<JIRA-ID>/` (no slug suffix) still
work for read access — `resolve_story_dir` only matches `<JIRA-ID>-*`, so a
plain `EXAMPLE-100/` folder will not be auto-resolved. Either rename to add a
slug or pass the full folder path explicitly.

## OpenSpec integration

`bash scripts/install.sh` now auto-installs `@fission-ai/openspec` via npm.
After install, run this once per target product repo:

```bash
openspec init
openspec config profile expanded   # enables /opsx:new, /opsx:continue, /opsx:ff, /opsx:verify
openspec update
```

**Hard boundary:** agent-skills-setup never writes inside `./openspec/`. Our
skills produce upstream evidence (intake, audit, repo scan) and downstream
evidence (apidog, tests, release). The `/audit-handoff` skill prints a
ready-to-run `/opsx:propose <change-id>` instruction; the user runs it and
OpenSpec creates `./openspec/changes/<change-id>/{proposal,design,tasks,specs}.md`.

### Change-id naming

| Trigger | Pattern | Example |
|---|---|---|
| Initial proposal | `<jira-id-lowercase>-<slug>` | `example-100-add-camera-group-filter` |
| Mid-implementation change request | `<jira-id-lowercase>-cr-<short-slug>` | `example-100-cr-group-permission` |
| Post-release bugfix | `<bug-id-lowercase>-fix-<short-slug>` | `bug-2034-fix-permission-leak` |

### Two trees, one bridge

```
./docs/stories/<JIRA-ID>-<slug>/   ← agent-skills-setup writes here
./openspec/changes/<change-id>/    ← OpenSpec writes here (never touched by our skills)
```

The bridge is `intake-summary.md` frontmatter:

```yaml
---
jira_story: EXAMPLE-100
openspec_changes:
  - example-100-add-camera-group-filter
  - example-100-cr-group-permission
status: implementing
---
```

`release/archive-check` walks this list to verify each change-id has been
archived in OpenSpec before considering the story complete.

## Kiro-specific changes

- **`~/.kiro/agents/default.json`** is now auto-generated by `bash scripts/install.sh --agent kiro`. Correct `name` (`kiro_default`) and explicit resource list replacing the broken glob. No manual editing needed.
- **`~/.kiro/prompts/`** is updated on every install with all group skill prompts (14 files).
- **`~/.kiro/steering/engineering-rules.md`** receives the 13-rule engineering rules (including Rule 13 — the spec-gated workflow gate). Deployed by `bash scripts/install-agents-md.sh`.

## Credentials are unchanged

Keychain entries (`agent-skills-setup:jira`, `agent-skills-setup:confluence`,
`agent-skills-setup:gemini`, `agent-skills-setup:anthropic`) and
`~/.agent-skills-setup/config.sh` keys are not touched by this refactor.

New in Phase 2: `agent-skills-setup:apidog` is used by `apidog/contract`,
`apidog/mocks`, and `apidog/testcases`. Set up with:

```bash
bash scripts/credentials/service.sh apidog add
```
