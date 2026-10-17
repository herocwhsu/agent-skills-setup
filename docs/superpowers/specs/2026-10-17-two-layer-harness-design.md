---
title: two-layer harness (harness repo + target repos)
date: 2026-10-17
status: draft
---

# two-layer harness

agent-skills-setup stays the one harness repo. hangar and atelier, and later
company repos (backend, frontend, infra, embedded), become target repos: the
agent is started in the target repo's root, and the harness reaches it through
the global install plus one machine-readable file in that repo. The agent never
reads that file; `AGENTS.md` stays the agent's guide.

## Problem (found 2026-10-16/17)

| # | Issue | Where |
|---|---|---|
| I1 | `sh-check.sh` is the 2026-08-20 copy; the template gained agy support on 2026-10-10 | hangar, atelier |
| I2 | `shared-hook-drift.sh` compares hangar with atelier, never with the harness, so I1 went unseen | hangar |
| I3 | Hooks are wired for Claude only; codex and agy run with no hooks there | hangar, atelier |
| I4 | No record of which harness version a repo was set up from | all target repos |
| I5 | Repo-specific values live inside each hook copy (`# --- repo config ---`), so copies must be edited and drift | hangar, atelier |
| I6 | `init-repo.sh` takes one profile; atelier needs python + js + k8s | harness |
| I7 | Commit format: atelier says "max 72" and drops `ci`/`security`; the global rule and hangar say ~72 with both | atelier |
| I8 | Commit format and Startup/Done/End-of-session sections repeat the global rules (~80% identical across repos) | hangar, atelier |
| I9 | Startup rule reads `PROGRESS.md` in full: ~3,900 tokens per session in hangar | hangar |
| I10 | All 34 skills are visible everywhere (~2,100 tokens of descriptions); Jira/Apidog/SRE skills invite wrong loads in hangar | all |
| I11 | Telemetry, run records and evaluation exist only in the harness repo | hangar, atelier |
| I12 | `AGENTS.md` front matter declares `verify_command` etc., but no script reads it | harness |
| I13 | hangar has no `feature_list.json`, atelier does; nothing says whether that is intended | hangar |
| I14 | No embedded (C/C++) or ansible hook pack | harness |

## Design

```
harness repo (agent-skills-setup)          target repo (hangar, atelier, ...)
  skills/   core + packs                     agent-harness.json   ← harness reads
  templates/hooks/ common + stacks           AGENTS.md / CLAUDE.md ← agent reads
  install.sh / update.sh  ───── sync ─────▶  .claude/hooks (harness copies, never edited)
  telemetry (central, per repo)  ◀─ runs ──  local hooks / own skills (repo owns)
```

- **Hooks, three layers:** common (every repo) → stack packs (any number:
  python, js, go, k8s, later ansible, c-cpp) → local hooks (repo-owned, never
  touched). Harness copies are byte-identical; per-repo values come from
  `agent-harness.json`. A hook only checks its own file types; a missing tool
  is a loud SKIP. A local hook used by a second repo moves into a pack.
- **Skills:** core skills stay global; packs (spec-gated, sre, ai, frontend,
  infra, harness-dev) are linked into `<repo>/.claude/skills/` only where the
  file lists them (links git-ignored, created by `update.sh`); a repo's own
  skills are committed.
- **One hook list → every agent's settings** (`.claude/settings.json`,
  `.codex/hooks.json`, `.agents/hooks.json`).
- **Session flow in a target repo:** load rules + `AGENTS.md` → SessionStart
  preflight (version, hook drift, state files, short state brief; warns, never
  blocks) → work (skills, per-edit hooks) → Stop gate runs the file's `verify`
  (blocks) → gate run recorded centrally → end of session updates `PROGRESS.md`.

## Tasks (WIP=1, in order)

Each task records `repo_audit` before and after, plus its own run record, so
the next task is planned from measured cost and effect.

| Task | Fixes | Metric it must move | Needs decision |
|---|---|---|---|
| T1 `repo_audit.py`: per-repo metrics (always-loaded tokens, startup-read tokens, hook drift vs harness, agents with hooks) | baseline for all | exists, reproducible | — |
| T2 sync drifted shared hooks into hangar, atelier | I1 | drift 1 → 0 per repo | — |
| T3 harness version: tags + install records installed commit | I4 | version recorded | — |
| T4 `agent-harness.json` schema, reader, files for hangar and atelier | I6, I12, I13 | both validate | D1, D6 |
| T5 per-repo hook values move from hook files into the file; drift check = byte compare; drop `shared-hook-drift.sh` | I2, I5 | harness copies identical | D2 |
| T6 `update.sh` syncs registered repos and writes hooks for every agent | I3, I6 | agents with hooks 1 → 3 | D3, D4 |
| T7 SessionStart preflight + state brief; startup rule reads the brief | I9 | hangar startup-read ~3,900 → ~300 tokens | D9 |
| T8 Stop runs `verify`; gate runs recorded centrally per repo | I11 | gate runs logged for target repos | D8 |
| T9 check per-repo skill support in codex, agy, kiro | (T10 input) | facts recorded | — |
| T10 skill packs per repo | I10 | hangar skill descriptions ~2,100 → ~700 tokens | D7 |
| T11 trim `AGENTS.md`: one commit rule, shared sections from a template | I7, I8 | repo `AGENTS.md` tokens down, no conflicts | D5 |
| T12 cross-repo trend in `trace-evaluation.sh` and the weekly review | I11 | one trend over all repos | — |
| later | ansible, c-cpp packs when a repo needs them | I14 | — | — |

## Open decisions (proposed default in bold)

- D1 file format: **`agent-harness.json`** (system Python 3.9 reads it) vs YAML (needs PyYAML).
- D2 per-repo hook values move into the file: **yes**.
- D3 `update.sh` syncs **every registered repo, printing what changed** vs one repo per run.
- D4 agents used in hangar/atelier: claude only, or claude + codex + agy. (no default)
- D5 commit format: **global rule everywhere, repo keeps only its exceptions**.
- D6 hangar `feature_list.json`: intended or missing. (no default)
- D7 spec-gated pack: company repos only, or atelier too. (no default)
- D8 target-repo telemetry: **central in the harness runtime dir, per repo** vs committed in each repo.
- D9 preflight on version drift: **warn** vs block.
