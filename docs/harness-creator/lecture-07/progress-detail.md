# Lecture 7 Training — Full Progress Detail

Companion to [summary.md](./summary.md). Date: 2026-10-07. Raw experiment files are in [raw/](./raw/).

---

## Step 0 — Baseline & Pre-checks

- Target repository: [`agent-skills-setup`](file:///Users/phoenix/projects/agent-skills-setup)
- Commit: `00205e0` (feat-039) on `main`
- Initial gate status: `./init.sh` passed clean across all gates.
- Lecture 6 open items recorded in `PROGRESS.md`:
  1. `What's Next` is an unordered prose list.
  2. `feature_list.json` has 39 completed features, but no schema enforcement for acceptance criteria or executable verification commands.
  3. No mechanical guard checked whether multiple features could be simultaneously active.

---

## Step 1 — Exercise 1: Task Atomization

We selected the real backlog item from `PROGRESS.md:172`:
> *"Optional: scope the Stop gate's tests to changed files so a stop no longer takes ~3 minutes."*

Decomposed into a 5-unit Directed Acyclic Graph (DAG) in [`code/task-atomization-plan.md`](code/task-atomization-plan.md):

1. **`F-ATOM-01`**: Changed-file detector CLI
   - Output: paths of modified/staged/untracked files.
   - Executable verification: `bash scripts/tests/test_changed_files_detector.sh`
   - Allowed paths: `scripts/get-changed-files.sh`, test script.
2. **`F-ATOM-02`**: Test-target resolver mapping
   - Output: maps changed source paths to test suites; triggers full-suite fallback on shared/infra files.
   - Executable verification: `python3 -m pytest tests/test_resolve_test_targets.py`
   - Allowed paths: `scripts/resolve_test_targets.py`, test file.
3. **`F-ATOM-03`**: Selective runner flag (`--changed` in `run-tests.sh`)
   - Output: executes only targeted tests, reports passed/failed counts.
   - Executable verification: `bash scripts/run-tests.sh --fast --changed`
   - Allowed paths: `scripts/run-tests.sh`, test file.
4. **`F-ATOM-04`**: Wire selective mode into `tests-guard.sh`
   - Output: Stop hook triggers fast selective tests on single-file modifications.
   - Executable verification: `bash .claude/hooks/tests-guard.sh`
   - Allowed paths: `.claude/hooks/tests-guard.sh`.
5. **`F-ATOM-05`**: Preserve full-suite invariants on `harness-verify.sh`
   - Output: manual `./init.sh`, CI, and full verification retain 100% test coverage.
   - Executable verification: `bash scripts/harness-verify.sh`
   - Allowed paths: `scripts/harness-verify.sh`, `docs/architecture.md`.

WIP=1 enforcement guarantees that `F-ATOM-02` through `F-ATOM-05` remain locked in `not_started` or `blocked` status until `F-ATOM-01` passes its verification command.

---

## Step 2 — Exercise 2: Comparison Experiment (Unconstrained vs. WIP=1)

- **Target Task:** Build `kvstore.py` (Key-Value Document Store CLI) supporting F1 (`put`/`get`), F2 (`delete`), F3 (`list --prefix`), F4 (`export --json`), and F5 (`stats`).
- **Sandbox Directories:** `/tmp/l7/exp-a` (Condition A) and `/tmp/l7/exp-b` (Condition B).
- **Independent Grader:** `/tmp/l7/testsuite/hidden_accept.py` (copied to [`raw/hidden_accept.py`](raw/hidden_accept.py)).
- **Subagents Dispatched:**
  - **Subagent A (`8711c888-2104-48ac-9fb5-5435aae797be`):** Unconstrained instructions ("implement as many of the 5 features as you can within budget").
  - **Subagent B (`29a8fce6-17c2-4c48-8988-ed023d0dc278`):** Strict WIP=1 instructions ("activate ONE feature at a time from queue F1->F2->F3->F4->F5; verify each before starting the next").

### Findings:
1. **Verification Score:** Both conditions reached 5/5 on the independent hidden acceptance suite.
2. **Code Volume:**
   - Condition A produced **125 lines** of code.
   - Condition B produced **86 lines** of code (31.2% reduction).
3. **Spec Creep & Overreach:**
   - Condition A pulled in `argparse` with complex subparser structures, added environment variable overrides (`KV_STORE_PATH`), unrequested positional arguments (`pos_prefix`), and polymorphic serialization logic.
   - Condition B wrote a lean, direct `sys.argv` router with zero unrequested features, keeping attention strictly on the active requirement.
4. **Testing Architecture:**
   - Condition A wrote a single test script `test_kvstore.py` run at the end.
   - Condition B wrote atomic test files (`test_f1.py` through `test_f5.py`), demonstrating incremental verification across the entire workflow.

---

## Step 3 — Exercise 3: Completion Evidence Audit & Harness Guard Implementation

We audited `agent-skills-setup`'s state layer and identified that `.claude/hooks/state-layer-guard.sh` only validated JSON parsing, completely ignoring:
- Whether multiple features were marked active simultaneously.
- Whether active features contained an executable verification command.

### TDD Implementation:
1. **Failing Test (RED):** Added test cases 8, 9, and 10 to `.claude/hooks/tests/test_state_layer_guard.sh` checking for:
   - Multiple active features blocking with exit 2 (`WIP limit violation`).
   - Active feature lacking verification command blocking with exit 2 (`Completion evidence missing`).
   - Single active feature with valid verification passing with exit 0.
   - Confirmed 4 tests failed.
2. **Implementation (GREEN):** Updated `.claude/hooks/state-layer-guard.sh` with python-based validation logic.
3. **Verification:** All 17 unit tests passed clean (`test_state_layer_guard.sh`).
4. **Tooling:** Implemented `docs/harness-creator/lecture-07/code/scope_tracker.py` and `test_scope_tracker.py` (passing).

---

## Step 4 — Repo Updates

- **`AGENTS.md`**: Added explicit WIP=1 constraint to `Startup Workflow` (item 5).
- **`PROGRESS.md`**: Updated header status to "Harness lectures: 1–7 closed". Restructured `What's Next` into an ordered, prioritized queue with verification commands.
- **Git Commit:** Kept completely uncommitted per user instruction (`not commit`).
