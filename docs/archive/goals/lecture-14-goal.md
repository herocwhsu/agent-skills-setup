# Goal Specification: Lecture 14 — Graph Engineering & Multi-Agent DAG State Machine

> Autonomous ratchet goal specification (feat-060)

## Goal

Study and close Lecture 14 ("From Single Loops to Graph Engineering"), porting the core Graph Engineering engine and multi-agent workflow DAG execution mechanisms into the harness with zero external dependencies (Python 3.9+ / 3.14 compatible, deterministic execution, checkpointer, and conditional rollback routing).

## Acceptance Criteria

- [x] Comprehensive Lecture 14 study materials created:
  - `docs/harness-creator/lecture-14/summary.md` (Concepts: 4 stacked layers, Loop vs Graph, 3 structural loop failures, Graph != Workflow, Anchors, Orchestration Tax, 5 graph criteria)
  - `docs/harness-creator/lecture-14/progress-detail.md` (Exercise log, measurements, and audit trails)
  - `docs/harness-creator/lecture-14/code/graph.md` (Blueprint of maker-checker graph with explicit node table, edge table, shared state, and routing rules)
- [x] Standalone, zero-dependency Graph Engine implementation:
  - `docs/harness-creator/lecture-14/code/graph_engine.py` (StateGraph, nodes, edges, conditional router, checkpointer, and pause-for-human approval)
  - `docs/harness-creator/lecture-14/code/test_graph_engine.py` (100% test coverage)
- [x] Production Harness Promotion:
  - Promote engine to `scripts/graph_runner.py` and `scripts/graph-runner.sh` CLI wrapper
  - Add test suites in `tests/test_graph_runner.py` and `scripts/tests/test_graph_runner.sh`
- [x] Zero Type or Lint Regressions:
  - `.venv/bin/mypy --config-file mypy.ini` clean across all files
  - `.venv/bin/ruff check` clean
- [x] All 11 Harness Verification Gates Clean:
  - `bash scripts/run-tests.sh --fast` passes with zero failures
  - `bash scripts/harness-verify.sh` passes all 11 gates cleanly
- [x] Adversarial Checker Verification:
  - Independent subagent review confirming Worker/Checker separation, rollback edges, and no fake success
- [x] Telemetry & State Invariants:
  - `feature_list.json` registers and completes `feat-060` with `WIP <= 1`
  - `python3 scripts/trace_evaluation.py --check-thresholds` passes `OK` (<6,000 state tokens)

## Scope

### Fair Game
- `docs/harness-creator/lecture-14/*`
- `docs/goals/lecture-14-goal.md`
- `scripts/graph_runner.py`
- `scripts/graph-runner.sh`
- `scripts/tests/test_graph_runner.sh`
- `tests/test_graph_runner.py`
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
   - `.venv/bin/ruff check docs/harness-creator/lecture-14/ scripts/ tests/`
   - `.venv/bin/mypy --config-file mypy.ini`
2. Test Suites:
   - `bash scripts/tests/test_graph_runner.sh`
   - `.venv/bin/pytest tests/test_graph_runner.py docs/harness-creator/lecture-14/code/test_graph_engine.py`
   - `bash scripts/run-tests.sh --fast`
3. Harness Gates:
   - `bash scripts/harness-verify.sh`
4. State Layer Guard:
   - `bash harness/guards/state-layer-guard.sh`
   - `/bin/bash harness/guards/state-layer-guard.sh`
   - `python3 scripts/trace_evaluation.py --check-thresholds`

## Stop Conditions

- Target criteria met (all 11 gates pass + independent checker reports CLEAN PASS)
- Max iterations: 5 rounds
- Consecutive failures: 3 consecutive failures halts the loop and flags human attention
- Rollback invariant: Any breaking change is reverted via `git reset`
