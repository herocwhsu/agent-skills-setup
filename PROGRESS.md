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
- Historical progress log pruned: `feat-001` through `feat-055` archived in `docs/progress-archive.md`.

## Status

### What's Done

*(Earlier features feat-001 through feat-055 are archived in [docs/progress-archive.md](docs/progress-archive.md). Per-feature evidence also recorded in `feature_list.json` and `docs/archive/features/`.)*

- [x] feat-056: Auto duration delta calculation, process tree agent detection, and Markdown trace dashboard. Upgraded `scripts/trace_evaluation.py` to auto-calculate elapsed duration since previous trace entries when `--duration-ms` is omitted, inspect process tree ancestry in `detect_agent()` via `get_process_ancestors()` (eliminating ambiguous directory checks), format times human-readably (ms, s, m, h), and auto-generate `docs/telemetry/SUMMARY.md` Markdown dashboard table on record. Added tests in `scripts/tests/test_trace_evaluation.sh` (12/12 passed).
- [x] feat-057: Subagent telemetry tracking (self subagents and outside agents) and independent review verification. Added execution logging (`_log_outside_run`) to `scripts/outside_agent.py` recording runs to both state and local telemetry (`docs/telemetry/outside-agent-runs.jsonl`, gitignored). Implemented subagent tracking in `scripts/trace_evaluation.py` (`--self-subagents`, `--outside-subagents`, auto-detection via `auto_detect_outside_runs`, defensive parsing against malformed lines and naive/aware datetimes, cross-platform Python 3.9+ compatibility). Updated `SUMMARY.md` and CLI trend table with Subagents column. Added unit tests in `scripts/tests/test_trace_evaluation.sh` (16/16 passed across all timezones) and `tests/test_outside_agent.py` (92 passed, 1 skipped). Adversarially reviewed across 5 iterative rounds with both self subagents and outside independent agents (Claude Code `outside-agent.sh`) achieving CLEAN PASS.
- [x] feat-058: Autonomous ratchet loop runner, goal specifications, and review iteration flow. Standardized goal specifications under docs/goals/ (TEMPLATE.md) defining machine-verifiable acceptance criteria, fair-game and hands-off scopes, and stopping conditions. Promoted ratchet_loop into scripts/ratchet_loop_runner.py and scripts/ratchet-loop.sh CLI runner with support for --goal-file, --active-feature, --review-diff, and --demo modes. Implemented automated verification, independent Checker review evaluation (via outside-agent.sh or custom checkers), automated rollback on regression, and circuit breakers. Added unit tests in tests/test_ratchet_loop_runner.py (5/5 passed) and scripts/tests/test_ratchet_loop.sh (6/6 passed across macOS system Python 3.9 and Python 3.14). All fast test suites and 11 harness gates pass.
- [x] feat-059: State layer context bloat remediation and feature archival (feat-051 through feat-055). Partitioned completed features feat-051 through feat-055 into docs/archive/features/archive-feat-051-055.json, updated feature_list.json archive_references, and pruned historical training decisions from PROGRESS.md into docs/progress-archive.md. State layer tokens reduced below 6,000 threshold (OK status in trace evaluation).
- [x] feat-060: Graph Engineering DAG runner, state machine orchestration, and Lecture 14 closing. Authored comprehensive Lecture 14 study materials (summary.md, progress-detail.md, code/graph.md). Implemented zero-dependency StateGraph engine in docs/harness-creator/lecture-14/code/graph_engine.py with checkpointer persistence, human-in-the-loop pause, and conditional rollback routing. Promoted to production CLI runner in scripts/graph_runner.py and scripts/graph-runner.sh. Added automated unit tests in docs/harness-creator/lecture-14/code/test_graph_engine.py (5/5 passed), tests/test_graph_runner.py (3/3 passed), and scripts/tests/test_graph_runner.sh (3/3 passed). Audited by independent adversarial subagent with CLEAN PASS verdict. Verified with run-tests.sh --fast (86/86 passed) and all 11 gates in harness-verify.sh.

- [x] feat-061: Weekly review report (`scripts/weekly-review.sh` → `docs/weekly/YYYY-Www.md`) and first self fine-tune. Found feat-058's verification command broken by the feat-059 rename (`tests/test_ratchet_loop.py` → `test_ratchet_loop_runner.py`), fixed it, added a stale-verification-path check to the weekly report, and listed the new runners in the README script table. Tests 9/9.

- [x] feat-062: Multi-Agent Team Topologies, Hierarchical Supervisor, and Consensus Voting (Lecture 15). Authored comprehensive study materials in `docs/harness-creator/lecture-15/` (summary.md, progress-detail.md, code/team_topology.md). Implemented zero-dependency team engine in `docs/harness-creator/lecture-15/code/team_engine.py` with Supervisor, WorkerPool (budget timeout check, isolated execution), and ConsensusEngine (majority, unanimous, security veto with error tolerance). Promoted to production CLI runner in `scripts/team_runner.py` and `scripts/team-runner.sh`. Added tests in `test_team_engine.py` (14/14), `tests/test_team_runner.py` (3/3), and `scripts/tests/test_team_runner.sh` (5/5). Audited by independent adversarial subagent; all conditional findings remediated.

### What's In Progress

- Nothing active (WIP=0, clean state).

### What's Next

**Prioritized Technical Queue (WIP=1):**
1. **Smoke test verification:** Re-run live `codex-kiro` and `agy` smoke tests against feat-033 fixes; trust repo hooks in Codex on each host.
   - *Verification:* `outside-agent.sh run --purpose review` exits 0.
2. **Fresh-session cross-repo tests:** Run fresh-session test on real `hangar` and `atelier` `main` once logged in headless.

**Pending Owner Decisions (Blocked on Human):**
- **daily-ai-video-pipeline:** Decide whether to create private remote GitHub repo or remain local.
- **Hermes cleanup:** Decide whether to drop residual `~/.hermes` configs from `skills/infra/kiro-gateway` or keep for other hosts.
- **Handy branch:** Decide if `local/zh-tw-default` needs further integration or remains fork-only.

## Blockers / Risks

- **`_lib.sh` pip step on Homebrew Python (PEP 668) [RESOLVED in feat-043]:** Replaced `--break-system-packages` with isolated runtime venv (`~/.agent-skills-setup/venv`) and automatic `site-packages` discovery.

- **`agy` latency varies by caller and environment (2026-10-08, cause unconfirmed):** a trivial
  `agy --dangerously-skip-permissions -p` prompt took 221s from the Claude Code session, above
  `outside-agent.sh`'s 110s default `--timeout`. The earlier `agy failed with an unclassified error`
  during a review is likely the same slowness, but it was not reproduced through the wrapper. Not a
  code defect. For a review that may fall through to `agy`, pass `--timeout 900`.

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

`Files Modified This Session`, `Evidence of Completion`, and historical features `feat-001` through `feat-055`
moved to [docs/progress-archive.md](docs/progress-archive.md). Per-feature evidence lives in `feature_list.json`
and `docs/archive/features/`.

## Notes for Next Session

Read `AGENTS.md` first — it documents real incidents (bash 3.2 target, symlinked
skills, hook exit codes) that are not obvious from the code alone. Then run
`./init.sh` to see current gate status before making changes.
