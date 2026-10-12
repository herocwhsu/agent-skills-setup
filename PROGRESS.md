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

### What's In Progress

- Nothing active (WIP=0, clean state).

### What's Next

**Prioritized Technical Queue (WIP=1):**
1. **[DONE 2026-10-12] Smoke test:** `outside-agent.sh run --purpose review` exited 0 in 16s via `codex-kiro`; `agy` answered directly in 12s. The `agy` fallback was not forced through the wrapper.
2. **[DONE 2026-10-12] Fresh-session cross-repo tests:** read-only `claude -p` sessions on `hangar` and `atelier` answered all five questions in ~46s each; the gaps they named were tool artifacts, not repo defects. `kiro-cli` and `gemini` `AGENTS.md` support is still untested.
3. **[DONE 2026-10-12] `agy` latency: not reproduced, cause unconfirmed.** 9 runs from this session took 7-15s (wrapper, direct, env-stripped), so the 2026-10-08 221s was likely a one-off; env inheritance has no effect. Fixed in `outside_agent.py`: a timeout now reads `agy(timeout after Ns)` and an empty reply `agy returned no output` (2 tests). Kept the 110s default.
4. **[DONE 2026-10-12] Cut the fresh-session context cost: 40.2k to 23.8k tokens (`claude -p /context`).** (a) `AGENTS.md` incident sections moved to `docs/incident-rules.md`; (b) `scripts/state_brief.py` replaces reading both state files in full (startup read 33.3 KB to 9.1 KB); (c) `ENABLE_TOOL_SEARCH=true` in `~/.claude/settings.json` defers MCP and rarely used built-in tools until a prompt needs them, saving about 16k in every repo; one `browser_navigate` run worked through the gateway. This host sets `ANTHROPIC_BASE_URL`, which turns tool search off by default. Remaining fixed costs the repo does not control: system prompt 6.6k, skills 7.4k, global `CLAUDE.md` 2.1k. To undo (c), delete the `ENABLE_TOOL_SEARCH` line.
   - *Verification:* before/after `claude -p /context` total, and `trace_evaluation.py --check-thresholds` OK.

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
