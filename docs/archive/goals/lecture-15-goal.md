# Goal Specification: Lecture 15 — Multi-Agent Team Topologies & Consensus Orchestration

> Autonomous ratchet goal specification (feat-062)
> Defines the goal, machine-verifiable criteria, scope boundaries, and stopping conditions.

## Goal

Extend the harness from single DAG workflows (Lecture 14) into **Multi-Agent Team Topologies & Consensus Orchestration**:
Implement a hierarchical supervisor pattern with dynamic worker pools and a multi-agent consensus voting engine (e.g. Architect, Security Auditor, QA Reviewer) with zero external dependencies, complete deterministic simulation tests, and production CLI harness runner.

## Acceptance Criteria

<!-- Machine-checkable conditions. Each criterion can be asserted with an automated command -->
- [x] Comprehensive Lecture 15 curriculum materials created under `docs/harness-creator/lecture-15/`:
  - `summary.md` (Theory: Hierarchical Supervisor, Dynamic Worker Pools, Peer Review vs Consensus, Byzantine/Hallucination tolerance, 4 Topology archetypes)
  - `progress-detail.md` (Detailed exercise breakdown, simulation metrics, failure modes)
  - `code/team_topology.md` (System topology blueprint, role specifications, consensus threshold formulas)
- [x] Standalone, zero-dependency Team & Consensus Engine:
  - `docs/harness-creator/lecture-15/code/team_engine.py` (Supervisor, WorkerPool, ConsensusEngine, quorum voting, unassisted fallback)
  - `docs/harness-creator/lecture-15/code/test_team_engine.py` (100% test coverage across topologies and consensus rules)
- [x] Production Harness Promotion:
  - Promote to production runner `scripts/team_runner.py` and `scripts/team-runner.sh`
  - Automated test coverage in `tests/test_team_runner.py` and `scripts/tests/test_team_runner.sh`
- [x] Zero Type or Lint Regressions:
  - `.venv/bin/mypy --config-file mypy.ini` clean across all modified files
  - `.venv/bin/ruff check` clean across all modified files
- [x] All 11 Harness Verification Gates Clean:
  - `bash scripts/run-tests.sh --fast` passes with zero failures
  - `bash scripts/harness-verify.sh` passes all 11 gates cleanly
- [x] Adversarial Checker Verification:
  - Independent subagent review confirming Worker/Supervisor separation, consensus veto mechanics, and test robustness
- [x] Telemetry & State Invariants:
  - `feature_list.json` registers and completes `feat-062` with `WIP <= 1`
  - `python3 scripts/trace_evaluation.py --check-thresholds` passes `OK` (<6,000 state tokens)
  - Working tree remains clean and tracked

## Scope

### Fair Game
- `docs/harness-creator/lecture-15/*`
- `docs/goals/lecture-15-goal.md`
- `scripts/team_runner.py`
- `scripts/team-runner.sh`
- `scripts/tests/test_team_runner.sh`
- `tests/test_team_runner.py`
- `feature_list.json`
- `PROGRESS.md`
- `docs/telemetry/*`

### Hands Off
- `AGENTS.md`
- `registry.txt`
- `scripts/_lib.sh`
- `harness/guards/`
- `.github/`

## Verification Method

1. Static Analysis:
   - `.venv/bin/ruff check docs/harness-creator/lecture-15/ scripts/ tests/`
   - `.venv/bin/mypy --config-file mypy.ini`
2. Test Suites:
   - `bash scripts/tests/test_team_runner.sh`
   - `.venv/bin/pytest tests/test_team_runner.py docs/harness-creator/lecture-15/code/test_team_engine.py`
   - `bash scripts/run-tests.sh --fast`
3. Harness Gates:
   - `bash scripts/harness-verify.sh`
4. State Layer Guard:
   - `bash harness/guards/state-layer-guard.sh`
   - `python3 scripts/trace_evaluation.py --check-thresholds`

## Stop Conditions

- Target criteria met (all acceptance criteria confirmed by independent Checker)
- Max rounds reached: 10
- Circuit breaker: 3 consecutive failed or regressed iterations halts the loop (Status: `BLOCKED`)
- Rollback invariant: Any iteration that fails tests or is rejected by the Checker is immediately rolled back (`git reset --hard`)
