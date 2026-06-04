# Migration: Flat Skills → Spec-Gated Groups

The 11 individual custom skills have been folded into 5 group skills. Same
scripts, same credentials, same outputs — only the wrapper SKILL.md, source
path, and slash command have changed.

This page maps every old slash command to its replacement so you can update
muscle memory after running `bash scripts/install.sh`.

## Slash command mapping

| Old slash | New slash | Notes |
|---|---|---|
| `/fetch-jira-story <ID>` | `/intake-jira-story <ID>` | Now writes to `./docs/stories/<JIRA-ID>-<slug>/` (slug derived from Jira summary) |
| `/fetch-page-to-markdown <URL>` | `/intake-web-page <URL>` | Same `./docs/pre-specs/` output for ad-hoc fetches; called internally by `/intake-jira-story` for embedded links |
| `/plan-story` | (retired) | Replaced by `/audit-handoff <ID>` + `/opsx:propose <change-id>` once Phase 2 lands. For Phase 1, use `Skill("superpowers:brainstorming")` then `Skill("superpowers:writing-plans")` directly. |
| `/create-story-tasks <ID>` | `/jira-subtasks <ID>` | Reads same `plan.md`/`tasks.md`, creates same Jira sub-tasks |
| `/mine-review-patterns [count]` | `/review-mine-patterns [count]` | Output still at `./.code-review/playbook.md` |
| `/review-pr <num>` | `/review-pr <num>` | Path unchanged; source moved to `skills/review/pr/` |
| `/confluence-tree-fetch <id>` | `/utils-confluence-tree-fetch <id>` | Self-hosted Server/DC migration only |
| `/confluence-tree-upload <dir> --parent <id> --space <KEY>` | `/utils-confluence-tree-upload ...` | Same args |
| `/confluence-link-rewrite-preview <dir> --parent <id>` | `/utils-confluence-link-rewrite-preview ...` | Same args |
| `polish-input` (hook, no slash) | `polish-input` (hook, no slash) | Hook command path updated to `${AGENT_SKILLS_DIR}/utils/polish-input/lib/polish.py` |
| `/kiro-gateway <sub>` | `/infra-kiro-gateway <sub>` | Subcommands unchanged: `init`, `update`, `rollback`, `status`, `setup-alias` |
| `/host-optimization` | `/infra-host-optimization` | `--revert` flag unchanged |

## Output folder layout

The single per-story root is now:

```
./docs/stories/<JIRA-ID>-<slug>/
```

Example: `./docs/stories/EXAMPLE-100-add-camera-group-filter/`

Pre-refactor stories under `./docs/stories/<JIRA-ID>/` (no slug suffix) still
work for read access — `resolve_story_dir` only matches `<JIRA-ID>-*`, so a
plain `EXAMPLE-100/` folder will not be auto-resolved. Either rename to add a
slug or pass the full path explicitly.

## OpenSpec is now installed via npm

`bash scripts/install.sh` now also runs `npm install -g @fission-ai/openspec`.
After install, in each target product repo run:

```bash
openspec init
openspec config profile expanded   # full slash-command set: /opsx:new, /opsx:continue, etc.
openspec update
```

OpenSpec owns `./openspec/changes/<change-id>/{proposal,design,tasks,specs}.md`.
agent-skills-setup never writes inside `./openspec/`. Phase 2 skills will print
recommended `/opsx:propose <change-id>` invocations rather than writing
proposal artifacts themselves.

## Two trees, one bridge

Story-level evidence (`./docs/stories/<JIRA-ID>-<slug>/`) and OpenSpec change
artifacts (`./openspec/changes/<change-id>/`) live in separate trees. The
bridge is `intake-summary.md` frontmatter (Phase 2):

```yaml
---
jira_story: EXAMPLE-100
openspec_changes:
  - example-100-add-camera-group-filter
status: implementing
---
```

For Phase 1, only the story tree exists; OpenSpec adoption begins as Phase 2
groups land.

## Credentials are unchanged

Keychain entries (`agent-skills-setup:jira`, `agent-skills-setup:confluence`,
`agent-skills-setup:gemini`, `agent-skills-setup:anthropic`) and
`~/.agent-skills-setup/config.sh` keys are not touched by this refactor.
