# Session Progress Log

## Current State

**Last Updated:** 2026-10-11
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
### What's In Progress

- Nothing active (WIP=0, clean state).

### What's Next

**Prioritized Technical Queue (WIP=1):**
1. **Run the benchmark when a harness change needs measuring.** `telemetry_benchmark.py run --runs 5` on the old and the new commit with the same `--model`, then `compare`. A clean tree is needed (a `-dirty` commit is not comparable). It costs about 50 sessions for 5 tasks x 5 runs x 2 versions.
2. **Capture gate results per task so run records have gate data.** Run `harness-verify.sh --report <path>` at the end of a task so a run record has gate data; no baseline run does.
3. **Record the error text when an outside agent fails (`classify` stays as is, decided 2026-10-13).** An unclassified failure logs only `result: error`, so a real 429 could not be told apart afterwards. Add a scrubbed `reason` (first 200 characters) to those attempt rows; return codes, order and classification do not change. Why not widen `classify`: the kiro gateway already retries 429 three times with backoff before the caller sees it, and a `rate_limit` result would bench both kiro agents until the 1st of next month. 14 attempts so far show no 429 or auth failure; the first real one will now carry its text. Do this together with the agy and claude-kiro timeout check.

**Pending Owner Decisions (Blocked on Human):**
- **daily-ai-video-pipeline:** Decide whether to create private remote GitHub repo or remain local.
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
