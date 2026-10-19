# Session Progress Log

## Current State

**Last Updated:** 2026-10-18
**Active Feature:** none
**Harness lectures:** 1–15 closed (`docs/harness-creator/lecture-0N/summary.md`).
- Lecture 10 (why end-to-end testing changes results) closed: e2e_runner ported (5/5 tests), review feedback promotion documented.
- Lecture 11 (making the agent's runtime observable) closed: runtime_logger ported (13/13 tests, clean ruff/mypy), sprint contract & evaluator rubric documented.
- Lecture 12 (why every session must leave a clean state) closed: cleanup_scanner and benchmark_runner ported (22/22 tests, clean ruff/mypy), Invariant 4 enforced via Gate 11.
- Lecture 13 (from manual prompting to autonomous loops) closed: ratchet_loop ported (9/9 tests, clean ruff/mypy), goal and loop state templates documented.
- Lecture 14 (from single loops to graph engineering) closed: graph_engine ported (8/8 tests, clean ruff/mypy), multi-agent DAG runner & rollback routing documented.
- Lecture 15 (multi-agent team topologies & consensus orchestration) closed: team_engine ported (17/17 tests, clean ruff/mypy), hierarchical supervisor, worker pool, and consensus runner documented.
- Historical progress log pruned: `feat-001` through `feat-060` archived in `docs/progress-archive.md`.

## Status

### What's Done

*(Earlier features feat-001 through feat-060 are archived in [docs/progress-archive.md](docs/progress-archive.md). Per-feature evidence also recorded in `feature_list.json` and `docs/archive/features/`.)*


- [x] feat-061: Weekly review report (`scripts/weekly-review.sh` → `docs/weekly/YYYY-Www.md`) and first self fine-tune. Found feat-058's verification command broken by the feat-059 rename (`tests/test_ratchet_loop.py` → `test_ratchet_loop_runner.py`), fixed it, added a stale-verification-path check to the weekly report, and listed the new runners in the README script table. Tests 9/9.

- [x] feat-062: Multi-Agent Team Topologies, Hierarchical Supervisor, and Consensus Voting (Lecture 15). Authored comprehensive study materials in `docs/harness-creator/lecture-15/` (summary.md, progress-detail.md, code/team_topology.md). Implemented zero-dependency team engine in `docs/harness-creator/lecture-15/code/team_engine.py` with Supervisor, WorkerPool (budget timeout check, isolated execution), and ConsensusEngine (majority, unanimous, security veto with error tolerance). Promoted to production CLI runner in `scripts/team_runner.py` and `scripts/team-runner.sh`. Added tests in `test_team_engine.py` (14/14), `tests/test_team_runner.py` (3/3), and `scripts/tests/test_team_runner.sh` (5/5). Audited by independent adversarial subagent; all conditional findings remediated.

- [x] feat-063: State-layer checks moved from the guard heredoc into `scripts/state_layer_check.py`; the guard exits 2 on any checker failure. Doc links are repo-relative. Reviewed by a fresh subagent and codex-kiro; guard tests 44/44.

- [x] feat-065: Run telemetry. `scripts/run_telemetry.py` reads session and subagent files into one JSON per run (`docs/telemetry/runs/`), `scripts/run_report.py` compares runs, and every outside-agent attempt is now logged. Reliability per metric: `docs/telemetry/RELIABILITY.md`. Spec and benchmark definition: `docs/stories/run-telemetry/`.

- [x] feat-066: Fixed telemetry benchmark. `python3 scripts/telemetry_benchmark.py run|compare` runs five fixed tasks in throwaway git repos and scores them with scripted checks; fixtures, hidden tests and reference solutions are in `benchmarks/telemetry/`. Method, checks and limits: `docs/stories/run-telemetry/benchmark.md`. One real run per task passed; the 5-run comparison has not been run.

- [x] feat-067: Faster gates and automatic run records. Tests run in parallel (gates take about 80 s instead of 220 s); every run record carries `process_adherence`; `session-clean.sh` attaches a summary to each completed feature and archives to keep the state layer under budget; outside-agent reviews default to 300 s and failed attempts log a scrubbed `reason`. See `docs/telemetry/RELIABILITY.md` and `docs/stories/run-telemetry/drift-check.md`.
- [x] feat-068: AGY statusline is one adaptive line (`[model] cwd git:(branch)   bar pct used/total │ 5h quota`) built from AGY's JSON payload, dropping fields to fit `terminal_width`. `install_statusline` and `setup-host.sh` now set `stack_with_default` false so AGY's native line no longer stacks with ours. Live check outstanding: whether the row still moves during a long response.

- [x] feat-069: AGY statusline shows output tokens (`out N`, dropped with the branch when narrow). The row-position check compared old and new scripts live: all ended on the bottom line, so nothing was changed for it and the one-off shift stays unexplained.

- [x] feat-070: Run records attach to the right feature. A completion that is not committed reports `completion not committed` and `session-clean.sh` writes no run record then; `harness-verify.sh` logs every run and each record shows `gate_runs`; the feat-068 and feat-069 summaries are rebuilt from their real records. Order at session end: commit the completion, run `session-clean.sh`, commit the telemetry (AGENTS.md).

- [x] feat-071: AGY `stack_with_default` fixed. AGY ignores it at the top level and drops a `false` inside `statusLine`, so the installer now writes no key and removes any stale one; `setup-host.sh` leaves a foreign AGY `statusLine` alone. feat-068's claim that stacking was turned off was wrong in effect (corrected in its evidence).

- [x] feat-072: AGY statusline shows the current model family's own 5-hour limit (Gemini -> `gemini-5h`, Claude/GPT -> `3p-5h`, else the lowest) instead of the lowest across families, which showed `5h 0%` on a Gemini session with 59% left. Out-of-range quota values and a non-object `model` no longer break the line. Open: the `3p-5h` mapping for Claude/GPT names is unconfirmed; the model's own weekly limit is not shown.

- [x] feat-073: The runtime drift gate also compares the installed AGY and Claude `statusline-command.sh` with `config/statusline-command.sh`, but only where `bash scripts/install.sh` can repair it (main checkout, agent in the saved selection, settings name the copy exactly). Prompted by the installed AGY copy running an older script after feat-072.

- [x] feat-074: Telemetry housekeeping. The gate-runs log is one append-only file per month (no lock, twelve months kept); a completed feature with no completion commit now says why (`completion not committed`, `feature_list.json is not tracked by git`, `git cannot read this repository`, `git is not available`, `no work tree...`, `not a git repository`) and `session-clean.sh` skips the run record for all but the last; `--min-rows 10` stops the small tail records nobody claims. A first lock-based log cap was dropped after two reviews showed it unsound.

- [x] feat-075: `scripts/repo_audit.py <repo> [--save]` measures a target repo: always-loaded tokens (rules, @imports, skill descriptions), state files, each hook identical/drifted/local against `templates/hooks`, and which agents have hooks. Baselines for hangar, atelier and this repo in `docs/telemetry/repos/`. It found drift both ways: atelier's `py-guard`/`ts-guard` are newer than the templates, so T2 must upstream before syncing.

- [x] feat-076: atelier's monorepo-aware `py-guard`/`ts-guard`/`ts-fix` are now the templates (app folders in `APP_DIRS`); drifted hooks synced, hangar 2 → 0, atelier 6 → 0, both `./init.sh` pass.

- [x] feat-077: `install.sh` writes `harness-version.json` (commit, describe, dirty, time) in the runtime dir; target repos compare against it.

- [x] feat-078: `agent-harness.json` + `harness_adapter.py check`; hangar and atelier files list their hooks exactly as wired today and pass.

- [x] feat-079: drift is checked against the harness templates (`harness_adapter.py drift`, `common/harness-drift.sh`); hangar's sibling drift hook is gone; D2 changed: values stay in config blocks.

- [x] feat-080: `harness_adapter.py sync/register/sync-all` + `common/agent-hook.sh`; hangar and atelier now wire their hooks for claude, codex and agy; `update.sh` syncs registered repos.

- [x] feat-081: `common/preflight.sh` at session start (Claude SessionStart; other agents via AGENTS.md): version, drift, and a PROGRESS.md brief, hangar ~476 tokens instead of 3,870.

- [x] feat-082: `common/verify-gate.sh` runs each repo's verify at Stop and logs runs to `~/.agent-skills-setup/telemetry/<repo>/`; hangar's full-validate.sh replaced; hook timeout field.

- [x] feat-083: per-repo skill folders recorded: Claude `.claude/skills`, Codex and agy `.agents/skills`, Kiro `.kiro/skills`; Codex user path mismatch recorded open.

- [x] feat-084: skill packs (`config/skill-packs.json`), `skill_packs` in agent-harness.json, and repo_audit's scoped projection: hangar skills 2,380 → 1,870 tokens (1,027 without spec-gated). The global switch waits for D7.

- [x] feat-085: hangar and atelier AGENTS.md defer to the global commit rule; atelier's conflicting max-72/type list removed.

- [x] feat-086: `repo_trend.py` gives one table over all target repos (audits and verify runs); the weekly review includes it.

### What's In Progress

- Nothing active (WIP=0, clean state).

### What's Next

**Prioritized Technical Queue (WIP=1):**
0. **Two-layer harness, T2-T15 done** (hook sync, version, `agent-harness.json`, preflight, global hooks, skill packs, cross-repo telemetry): [the design](docs/superpowers/specs/2026-10-17-two-layer-harness-design.md), D1-D11. Owner action left: the global rules. Editing `agents/engineering-rules.md` and running `install-agents-md.sh` are denied to the agent as self-modification; the deployed copy predates the source (feat-089). After the owner deploys, add the shared repo-workflow rule (text in feat-091's session) and cut the Startup / End of Session wording from hangar and atelier. Also: atelier's react-router exceptions expire 2027-01-18; the real fix is react-router 7.
   - *Metric caveat:* feat-075's run record (`5a0ad1e4-ec73a5038f`, 1.3M output tokens, ~17 days) covers this whole long session from its start (hangar UPS work included), because the session had no earlier record. Start each T-task in a fresh session, or mark the window at activation, so its record measures only that task.
1. **Save gate output to a file inside `harness-verify.sh`** (only if the one-off 94/1 tests-gate failure from feat-068 comes back; it did not in six reruns). Until then, run it as `bash scripts/harness-verify.sh > file 2>&1`.
2. **Run the benchmark when a harness change needs measuring.** `telemetry_benchmark.py run --runs 5` on the old and the new commit with the same `--model`, then `compare`. A clean tree is needed (a `-dirty` commit is not comparable). It costs about 50 sessions for 5 tasks x 5 runs x 2 versions.
3. **Rerun `scripts/gate_experiment.py` before changing any gate** and read `docs/stories/run-telemetry/gate-necessity.md`. The first run (2026-10-13) recommends removing nothing.

- **Review of 2026-10-18's work (f0e08e1..9675bee + hangar, atelier):** fresh-context subagent found 9 defects, all confirmed and fixed (2243f9b, hangar 2c30578); the outside review was **not independent**: agy timed out at 1500s on the ~6,600-line diff and outside-agent fell back to claude (exit 3). Its 3 confirmed findings fixed in 48127c6. Next time review per repo or per feature so agy can finish.
- **Second outside review, split in five parts (2026-10-18):** C (weekly), D (hangar), E (atelier) ran on agy, independent; A (hooks) and B (adapter, install) timed out at 1200s on agy and fell back to claude, **not independent**. Findings fixed with failing tests first: ts-guard passed `-q`, which ESLint 9 rejects (exit 2, so every frontend turn was blocked); now `--quiet`, errors only, as ESLint 9 counts warnings against `--max-warnings` even with `--quiet` (atelier has 6 warnings, 0 errors). `store-packs` moves only names this install put there, and links only into this repo's `skills/` (a user's own `review/` was moved, then deleted by uninstall). A malformed `.claude/settings.json`, `.codex/hooks.json` or `.agents/hooks.json` stops sync instead of being overwritten. Global wiring prunes an old `global-hook.sh` entry whose command changed, so it cannot run twice. `record_harness_version` no longer fails an install. Not changed: sync owns the Claude `hooks` key by design (comment fixed). agy now reviews at `--effort high` (2026-10-19; delegate keeps the default): high finished a small review in 213 s, medium 274 s, while the default printed its answer and then hung until the 300 s timeout, so agy's own time varies more than effort does. The review default timeout is now 1200 s (was 300): real agy reviews took 590 to 1048 s, three more timed out at 1200 to 1500 s. Still unknown: how much of that is agy hanging after its answer. Re-review: agy (independent) found nothing; the subagent found the install list shared by all agents (claude installing `audit` made codex's own `audit/` look installed: moved, then deleted), fixed with a per-agent list; the prune marker is now this runtime's own path (another harness repo's global hook stays); sync reads every agent file before writing any, a blank file counts as empty, and a non-UTF-8 or non-object file stops sync too (third pass).
- **Live-run each agent's hooks after a wiring change**, not only replays from the repo root: replays missed both agy bugs in feat-087. A live agy run in a scratch clone (`agy -p ... --mode accept-edits`) is enough; a codex one when codex is installed.

- **Codex user skills path:** `agent_skills_dir codex` installs to `~/.codex/skills`; current Codex docs read `~/.agents/skills` (docs/harness-adoption.md). Codex is not installed here; check on a host that has it before changing the path.

**Pending Owner Decisions (Blocked on Human):**
- **firstdigital-economics:** Decide whether to create private remote GitHub repo or remain local.
- **Hermes cleanup:** Decide whether to drop residual `~/.hermes` configs from `skills/infra/kiro-gateway` or keep for other hosts.
- **Handy branch:** Decide if `local/zh-tw-default` needs further integration or remains fork-only.

## Blockers / Risks

- **`_lib.sh` pip step on Homebrew Python (PEP 668) [RESOLVED in feat-043]:** Replaced `--break-system-packages` with isolated runtime venv (`~/.agent-skills-setup/venv`) and automatic `site-packages` discovery.

- **`agy` latency is intermittent (2026-10-08, cause unconfirmed):** a trivial
  `agy --dangerously-skip-permissions -p` prompt took 221s once from the Claude Code session, above
  `outside-agent.sh`'s 110s default `--timeout`. On 2026-10-12, 9 runs took 7-15s in every condition
  (see queue item 3). If it recurs, record the time and whether `agy` was cold. For a review that may
  fall through to `agy`, pass `--timeout 900`.

## Decisions Made

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

`Files Modified This Session`, `Evidence of Completion`, and historical features `feat-001` through `feat-060`
moved to [docs/progress-archive.md](docs/progress-archive.md). Per-feature evidence lives in `feature_list.json`
and `docs/archive/features/`.

## Notes for Next Session

Read `AGENTS.md` first — it documents real incidents (bash 3.2 target, symlinked
skills, hook exit codes) that are not obvious from the code alone. Then run
`./init.sh` to see current gate status before making changes.
