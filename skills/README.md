# Skills

Custom agent skills managed by this repo. Each group follows the
[agentskills.io](https://agentskills.io) standard and works with Kiro, Claude Code,
Gemini, and Codex.

Skills are **two-level**: a group owns `SKILL.md` (the entry point the agent reads),
and each subcommand under it owns an `IMPL.md` recipe. There are currently 14 groups
and 41 subcommands.

```
skills/
└── <group>/
    ├── SKILL.md              ← required: group entry point + frontmatter
    ├── <subcommand>/
    │   ├── IMPL.md           ← required: the recipe for this subcommand
    │   ├── lib/              ← optional: scripts the recipe calls
    │   └── tests/            ← optional: tests for those scripts
    └── README.md             ← optional: human-readable usage guide
```

## Spec-gated workflow groups

Listed in roughly the order a production story moves through them. The gate sequence
itself is documented in [Spec-Gated Workflow](../README.md#spec-gated-workflow).

| Group | Subcommands | What it does |
|---|---|---|
| [intake](intake/SKILL.md) | `jira-story` `web-page` `spec-summary` | Bring outside specs into `./docs/stories/<JIRA-ID>-<slug>/` |
| [audit](audit/SKILL.md) | `spec` `domain-risk` `handoff` | Audit the spec for gaps and domain risk, then hand off to `/opsx:propose` |
| [repo](repo/SKILL.md) | `context-scan` `domain-notes` | Read the target codebase before writing a proposal |
| [external](external/SKILL.md) | `deps` | Document an unresolved vendor dependency and mock it so work isn't blocked |
| [apidog](apidog/SKILL.md) | `contract` `mocks` `testcases` `diff` | Plan and push the API contract, mocks, and test cases to Apidog |
| [testing](testing/SKILL.md) | `plan` `write` `regression` `qa-check` | Plan tests before implementation, scaffold RED tests, verify coverage |
| [jira](jira/SKILL.md) | `subtasks` `evidence` | Create sub-tasks from the approved plan; verify evidence links before closure |
| [review](review/SKILL.md) | `pr` `mine-patterns` `guardrails` `amend` `change-request` | Review PRs, diff implementation against the proposal, capture amendments |
| [release](release/SKILL.md) | `readiness` `triage` `bugfix-spec` `archive-check` | Final gates before and after production |
| [progress](progress/SKILL.md) | `status` | Report which gates a story has passed — derived from artifact files, not a tracker |

## Standalone groups

Not part of the spec-gated workflow; these run on their own.

| Group | Subcommands | What it does |
|---|---|---|
| [infra](infra/SKILL.md) | `kiro-gateway` `host-optimization` `apidog-mcp` `tmux-yank` `ups` | Local infrastructure behind Claude Code and Kiro workflows |
| [utils](utils/SKILL.md) | `polish-input` `confluence-tree` `skill-eval` | Cross-cutting helpers that belong to no single gate |
| [ai-stack](ai-stack/SKILL.md) | `baml` `langgraph` `memu` `ai-hedge-fund` | Reference material for adding AI/LLM features to a service |
| [experiment-iteration](experiment-iteration/SKILL.md) | — | Hypothesis → experiment → learning loops for exploratory work |

## Adding a skill

The root README is the single source of truth for this, so it isn't repeated here:

- [Add a subcommand to an existing group](../README.md#add-a-subcommand-to-an-existing-group)
- [Add a brand-new group](../README.md#add-a-brand-new-group)
- [Add an external skill or Claude Code plugin](../README.md#add-an-external-skill-or-claude-code-plugin)

A new local group needs one line in [`../registry.txt`](../registry.txt) —
`local <group>`, or `local-optional <group>` for one that installs only on request.
`bash ../scripts/install.sh` deploys it. `registry.txt` supports six other entry
types for external sources: `github`, `github-skill`, `plugin`, `plugin-optional`,
`npm`, and `pip`. The root README's
[external-source examples](../README.md#add-an-external-skill-or-claude-code-plugin)
cover the first four; `npm` and `pip` install a published package as a skill.

## Naming

- Lowercase with hyphens: `host-optimization` ✓
- No spaces, underscores, or capitals

## What this repo does not manage

Skills from [superpowers](https://github.com/obra/superpowers) (brainstorming, TDD,
systematic-debugging, and the rest) are installed from the upstream repo via
`registry.txt`. Update them with `bash ../scripts/update.sh`.
