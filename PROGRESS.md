# Session Progress Log

## Current State

**Last Updated:** 2026-10-22
**Active Feature:** none
**Harness lectures:** 1–15 closed (`docs/harness-creator/lecture-0N/summary.md`).
- Lecture 10 (why end-to-end testing changes results) closed: e2e_runner ported (5/5 tests), review feedback promotion documented.
- Lecture 11 (making the agent's runtime observable) closed: runtime_logger ported (13/13 tests, clean ruff/mypy), sprint contract & evaluator rubric documented.
- Lecture 12 (why every session must leave a clean state) closed: cleanup_scanner and benchmark_runner ported (22/22 tests, clean ruff/mypy), Invariant 4 enforced via Gate 11.
- Lecture 13 (from manual prompting to autonomous loops) closed: ratchet_loop ported (9/9 tests, clean ruff/mypy), goal and loop state templates documented.
- Lecture 14 (from single loops to graph engineering) closed: graph_engine ported (8/8 tests, clean ruff/mypy), multi-agent DAG runner & rollback routing documented.
- Lecture 15 (multi-agent team topologies & consensus orchestration) closed: team_engine ported (17/17 tests, clean ruff/mypy), hierarchical supervisor, worker pool, and consensus runner documented.
- Historical progress log pruned: `feat-001` through `feat-086` archived in `docs/progress-archive.md`.

## Status

### What's Done

*(Earlier features feat-001 through feat-086 are archived in [docs/progress-archive.md](docs/progress-archive.md); feat-087 to feat-094 in `docs/archive/features/`, feat-095 onward in `feature_list.json`. Per-feature evidence also recorded in `feature_list.json` and `docs/archive/features/`.)*


### What's In Progress

- Nothing active (WIP=0). feat-101 (kiro prompts only for skills in the global dir; 11 pointed at pack skills) done 2026-10-23; before it feat-100 (preflight warns above registered repos). feat-102 done too: ~/.gemini/skills (Gemini CLI only, unmanaged since 2026-07-04) backed up to ~/.agent-skills-setup/backup/ and removed, Gemini CLI uninstalled; agy reads ~/.gemini/config/skills, unaffected. Other hosts: check ~/.kiro/prompts (rerun install.sh) and ~/.gemini/skills by hand. Codex not installed here; its dirs stay (owner decision 2026-10-23). Planned from the 2026-10-23 architecture review, in this order: feat-103 lecture runners out of scripts/ and orphans deleted (done), feat-104 delete the pack kiro prompts (done; drop RETIRED_KIRO_PROMPTS in _lib.sh once every host reran install.sh), feat-107 py-guard pip-audit flag and agent-hook Codex move targets (done, synced to atelier and hangar), feat-105 this repo calls the templates directly (option c, env-var knobs for its stricter checks), feat-106 architecture.md rewrite last. Flaky under load (passed 3/3 alone, failed while subagents ran): scripts/tests/test_init_sh.sh "pip never started" (twice on 2026-10-23) and test_outside_agent.py SIGTERM returncode -15.
- Planned 2026-10-23, from hangar's four-run vm1 reboot (hangar PROGRESS "In flight"): feat-097 handover-script contract, feat-098 cleanup steps name their cause, feat-099 failed gates print a diagnosis, feat-100 preflight warns above several repos (done). Start each in a session launched in this repo.- Follow-up: `harness/guards/secret-scan.sh`, this repo's own whole-tree gate, still runs gitleaks `--no-git` over ignored files; apply the same copy if it gets slow or noisy.

### What's Next

**Prioritized Technical Queue (WIP=1):**
0. **Two-layer harness, T2-T15 done** (hook sync, version, `agent-harness.json`, preflight, global hooks, skill packs, cross-repo telemetry): [the design](docs/superpowers/specs/2026-10-17-two-layer-harness-design.md), D1-D11. The global rules, with the repo-workflow rule, are deployed (2026-10-18; redeployed 2026-10-19 with the review-output rule), and hangar (`2fef197`) and atelier dropped their duplicate Startup and End of Session wording. Also: atelier's react-router exceptions expire 2027-01-18; the real fix is react-router 7.
   - *Metric caveat:* feat-075's run record (`5a0ad1e4-ec73a5038f`, 1.3M output tokens, ~17 days) covers this whole long session from its start (hangar UPS work included), because the session had no earlier record. Start each T-task in a fresh session, or mark the window at activation, so its record measures only that task.
1. **Save gate output to a file inside `harness-verify.sh`** (only if the one-off 94/1 tests-gate failure from feat-068 comes back; it did not in six reruns). Until then, run it as `bash scripts/harness-verify.sh > file 2>&1`.
2. **Run the benchmark when a harness change needs measuring.** `telemetry_benchmark.py run --runs 5` on the old and the new commit with the same `--model`, then `compare`. A clean tree is needed (a `-dirty` commit is not comparable). It costs about 50 sessions for 5 tasks x 5 runs x 2 versions.
3. **Rerun `scripts/gate_experiment.py` before changing any gate** and read `docs/stories/run-telemetry/gate-necessity.md`. The first run (2026-10-13) recommends removing nothing.

- **Review of 2026-10-18's work (f0e08e1..9675bee + hangar, atelier):** fresh-context subagent found 9 defects, all confirmed and fixed (2243f9b, hangar 2c30578); the outside review was **not independent**: agy timed out at 1500s on the ~6,600-line diff and outside-agent fell back to claude (exit 3). Its 3 confirmed findings fixed in 48127c6. Next time review per repo or per feature so agy can finish.
- **Second outside review, split in five parts (2026-10-18):** C (weekly), D (hangar), E (atelier) ran on agy, independent; A (hooks) and B (adapter, install) timed out at 1200s on agy and fell back to claude, **not independent**. Findings fixed with failing tests first: ts-guard passed `-q`, which ESLint 9 rejects (exit 2, so every frontend turn was blocked); now `--quiet`, errors only, as ESLint 9 counts warnings against `--max-warnings` even with `--quiet` (atelier has 6 warnings, 0 errors). `store-packs` moves only names this install put there, and links only into this repo's `skills/` (a user's own `review/` was moved, then deleted by uninstall). A malformed `.claude/settings.json`, `.codex/hooks.json` or `.agents/hooks.json` stops sync instead of being overwritten. Global wiring prunes an old `global-hook.sh` entry whose command changed, so it cannot run twice. `record_harness_version` no longer fails an install. Not changed: sync owns the Claude `hooks` key by design (comment fixed). agy now reviews at `--effort high` (2026-10-19; delegate keeps the default): high finished a small review in 213 s, medium 274 s, while the default printed its answer and then hung until the 300 s timeout, so agy's own time varies more than effort does. The review default timeout is now 1200 s (was 300): real agy reviews took 590 to 1048 s, three more timed out at 1200 to 1500 s. Timed run on 01bc362 (high, stream-json, 2026-10-19): 1028 s, exited right after its answer (no hang); 777 s in 74 model turns, 242 s in 72 tools (commands 152 s, waits 81 s); it also ran the fast suite it was not asked for and spent a dozen turns waiting on tests; the answer began at 912 s. It found the non-object JSON root defect that 8e4765c fixed. Re-review: agy (independent) found nothing; the subagent found the install list shared by all agents (claude installing `audit` made codex's own `audit/` look installed: moved, then deleted), fixed with a per-agent list; the prune marker is now this runtime's own path (another harness repo's global hook stays); sync reads every agent file before writing any, a blank file counts as empty, and a non-UTF-8 or non-object file stops sync too (third pass).
- **Live-run each agent's hooks after a wiring change**, not only replays from the repo root: replays missed both agy bugs in feat-087. A live agy run in a scratch clone (`agy -p ... --mode accept-edits`) is enough; a codex one when codex is installed.

- **Codex user skills path:** `agent_skills_dir codex` installs to `~/.codex/skills`; current Codex docs read `~/.agents/skills` (docs/harness-adoption.md). Codex is not installed here; check on a host that has it before changing the path.

**Pending Owner Decisions (Blocked on Human):**
- **firstdigital-economics:** Decide whether to create private remote GitHub repo or remain local.
- **Handy branch:** synced with upstream and pushed 2026-10-22 (fork `main` and `local/zh-tw-default`); owner to test the build at the Mac before this is closed.

## Blockers / Risks

- **`_lib.sh` pip step on Homebrew Python (PEP 668) [RESOLVED in feat-043]:** Replaced `--break-system-packages` with isolated runtime venv (`~/.agent-skills-setup/venv`) and automatic `site-packages` discovery.

- **`agy` latency is intermittent (2026-10-08, cause unconfirmed):** a trivial
  `agy --dangerously-skip-permissions -p` prompt took 221s once from the Claude Code session, above
  `outside-agent.sh`'s 110s default `--timeout`. On 2026-10-12, 9 runs took 7-15s in every condition
  (see queue item 3). If it recurs, record the time and whether `agy` was cold. For a review that may
  fall through to `agy`, pass `--timeout 900`.

## Decisions Made

- **Hermes configs stay (owner, 2026-10-21):** `skills/infra/kiro-gateway` keeps its
  `~/.hermes` configs for other hosts.
- **A fresh context makes a reviewer independent (owner, 2026-10-20):** whatever its model
  family; `outside-agent.sh` no longer exits 3 for a same-family review. High-risk changes get
  two subagents in parallel (correctness; security and permissions); an outside agent is
  optional and never holds the commit (owner, after agy spent 4,792 s on 9 attempts for 2
  answers). agy reviews on `gemini-3.8-flash-high`.
- **Case-sensitive filesystem assumed repo-wide (owner, 2026-10-07):** All host environments, Docker
  containers, and CI operate on case-sensitive filesystems. New hooks and guards must not add
  case-insensitive fallback logic (e.g. checking both lowercase and uppercase variations).
  The legacy `progress.md` fallback in `state-layer-guard.sh` is removed.
- **Retain `feature_list.json` without symlinks (owner, 2026-10-07):** Keep the canonical name
  `feature_list.json` to preserve compatibility with external harness scanners (`validate-harness.mjs`
  in the harness-creator skill; `repo-reader.ts` and `feature-list-validator.ts` in the
  learn-harness-engineering course repo). Both course tools are ported to Python under
  `docs/harness-creator/lecture-03/code/` and `lecture-08/code/`; the validator is adapted to this
  repo's schema, since the original expects a bare array with `passes`/`verification`. No alias
  symlinks (`feature-list.json`).
- **Lecture-07 layout stays as is (2026-10-08):** `task-atomization-plan.md` remains in `code/` and
  `hidden_accept.py` in `raw/`. Lecture-06 keeps its grader in `raw/` and lecture-04 has no `raw/`,
  so there is no L4/L6 layout to match. Only the `cmp-*-report.md` to `cmp-*-s1.md` rename followed lecture-06.
- **Auto-merge in hangar and atelier stays (owner, 2026-10-01):** Renovate automerge and
  the macmini agents' direct pushes continue until scale-up or a significant incident.
  The rule is now recorded in both repos' `PROGRESS.md` and `AGENTS.md`, so a session
  there can read it without this repo's memory.

*(Historical training & exclusion-test decisions archived in [docs/progress-archive.md](docs/progress-archive.md).)*

## Archived history

`Files Modified This Session`, `Evidence of Completion`, and historical features `feat-001` through `feat-086`
moved to [docs/progress-archive.md](docs/progress-archive.md). Per-feature evidence lives in `feature_list.json`
and `docs/archive/features/`.

## Notes for Next Session

Read `AGENTS.md` first — it documents real incidents (bash 3.2 target, symlinked
skills, hook exit codes) that are not obvious from the code alone. Then run
`./init.sh` to see current gate status before making changes.
