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
  touched). Harness copies match their templates outside the repo config block (D2). A hook only checks its own file types; a missing tool
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

## Baseline (2026-10-17, `repo_audit.py`)

| Repo | Always loaded | State files | Hooks identical / drifted / local | Agents with hooks |
|---|---|---|---|---|
| hangar | ~5,400 tok | ~3,870 | 4 / 2 / 2 | claude |
| atelier | ~5,000 tok | ~1,250 | 4 / 6 / 0 | claude |

Drift runs both ways: some repo copies are older than the template, but atelier's
`py-guard`/`ts-guard` (2026-10-13, monorepo-aware) are newer and were never
upstreamed. A sync must never just overwrite a repo copy.

## Tasks (WIP=1, in order)

Each task records `repo_audit` before and after, plus its own run record, so
the next task is planned from measured cost and effect.

| Task | Fixes | Metric it must move | Needs decision |
|---|---|---|---|
| T1 ✅ feat-075 `repo_audit.py`: per-repo metrics (always-loaded tokens, state-file tokens, hook drift vs harness, agents with hooks) | baseline for all | baselines 2026-10-17 in `docs/telemetry/repos/` | — |
| T2 ✅ feat-076 upstream atelier's newer hooks (py-guard, ts-guard, …) into templates, then sync the older copies in hangar and atelier | I1 | drifted hooks hangar 2 → 0, atelier 6 → 0 | — |
| T3 ✅ feat-077 harness version: tags + install records installed commit | I4 | version recorded | — |
| T4 ✅ feat-078 `agent-harness.json` schema, reader, files for hangar and atelier | I6, I12, I13 | both validate | D1, D6 |
| T5 ✅ feat-079 drift checked against templates outside the config block (D2 changed); drop `shared-hook-drift.sh` | I2, I5 | harness copies identical | — |
| T6 ✅ feat-080 `update.sh` syncs registered repos and writes hooks for every supported agent, installed or not | I3, I6 | agents with hooks 1 → 3 | D3 |
| T7 ✅ feat-081 SessionStart preflight + state brief; startup rule reads the brief | I9 | hangar startup-read ~3,900 → ~300 tokens | D9 |
| T8 ✅ feat-082 Stop runs `verify`; gate runs recorded centrally per repo | I11 | gate runs logged for target repos | D8 |
| T9 ✅ feat-083 check per-repo skill support in codex, agy, kiro | (T10 input) | facts recorded | — |
| T10 skill packs per repo | I10 | hangar skill descriptions ~2,100 → ~700 tokens | D7 |
| T11 trim `AGENTS.md`: one commit rule, shared sections from a template | I7, I8 | repo `AGENTS.md` tokens down, no conflicts | D5 |
| T12 cross-repo trend in `trace-evaluation.sh` and the weekly review | I11 | one trend over all repos | — |
| later | ansible, c-cpp packs when a repo needs them | I14 | — | — |

## Open decisions (proposed default in bold)

- D1 file format: **`agent-harness.json`** (system Python 3.9 reads it) vs YAML (needs PyYAML).
- D2 ✅ changed 2026-10-18: **values stay in each hook's repo config block**, the only part a repo may
  edit. They are bash (arrays, regexes, `$REPO_ROOT` paths); JSON would need an eval loader in every
  hook. The drift came from comparing siblings, so copies are now compared with their templates
  (`harness_adapter.py drift`, `common/harness-drift.sh`).
- D3 `update.sh` syncs **every registered repo, printing what changed** vs one repo per run.
- D4 ✅ decided 2026-10-17: **every supported agent, whatever a host has installed.** A target repo
  gets hook settings for claude, codex and agy (kiro has no hook equivalent) even on a host with
  only claude and agy, so a repo works the same on any machine or clone.
- D5 commit format: **global rule everywhere, repo keeps only its exceptions**.
- D6 hangar `feature_list.json`: intended or missing. (no default)
- D7 spec-gated pack: company repos only, or atelier too. (no default)
- D8 target-repo telemetry: **central in the harness runtime dir, per repo** vs committed in each repo.
- D9 preflight on version drift: **warn** vs block.
