# Lecture 12 Detailed Execution Log

**Date:** 2026-10-10  
**Focus:** Leave a Clean Handoff at the End of Every Session (Lehman's Laws of Software Evolution, Broken Windows in Repositories, 5 Invariants of Clean State, Dual-Mode Cleanup Loops, Benchmark Comparison Runner).  
**Repository:** `agent-skills-setup`  
**Related summary:** [summary.md](./summary.md)  
**Code artifacts:** [code/](./code/)

---

## 1. Objectives & Context

Lecture 12 emphasizes that long-term reliability of AI coding agents depends on operational discipline and leaving a deterministic clean state at the end of every development session:
1. **Entropy Growth**: Without active cleanup, software entropy compounds exponentially across agent sessions.
2. **Broken Windows Effect**: Agents copy whatever patterns they find in the repo; leaving temporary hacks or uncommitted debris normalizes debt.
3. **Five Invariants of Clean State**:
   - Build passes cleanly.
   - All tests pass (no regressions).
   - Progress recorded in repository system of record (`feature_list.json`, `PROGRESS.md`).
   - No stale artifacts, scratch scripts, or uncommitted environment files.
   - Standard startup path (`./init.sh`) works immediately for the next session.
4. **Dual-Mode Cleanup Architecture**:
   - Immediate reference-counting cleanup at every session exit.
   - Periodic scheduled cleanup loops scanning for structural drift.
5. **Benchmark Comparison Slices**:
   - Evaluating harness modifications against repeatable task suites with automated delta calculation.

---

## 2. Ported Code Artifacts

### 2.1 Cleanup Scanner (`code/cleanup_scanner.py`)
- Ported from `cleanup-scanner.ts` to typed Python 3.12+ (PEP 604, PEP 695 style).
- Scans target project directories across 5 distinct categories:
  - **Stale Artifacts**: `.tmp`, `.bak`, `.swp`, `~`, and stray `.log` files in source trees.
  - **Dead Code**: Unfinished debt markers (`TODO:`, `FIXME:`, `HACK:`, `XXX:`).
  - **Structural Violations**: Missing `.gitignore`, nested build outputs (`src/dist`, `lib/build`), nested `node_modules`.
  - **Session Cleanliness**: Leftover session markers (`WIP.md`, `IN_PROGRESS.md`, `scratch.py`, `debug.py`) and empty directories.
  - **Configuration Hygiene**: Uncommitted environment files (`.env`, `.env.local`, `.env.production`).
- Supports structured JSON reporting (`--json`) and console table formatting.
- Unit tested via `code/test_cleanup_scanner.py` with 10 comprehensive test cases.

### 2.2 Benchmark Runner (`code/benchmark_runner.py`)
- Ported from `benchmark-runner.ts` to typed Python.
- Provides `BenchmarkTask` and `BenchmarkResult` data models.
- Executes benchmark task suites, checks pass criteria completion, and profiles expected vs actual duration deltas.
- Implements `compare_benchmarks(harness_a, harness_b)` computing completion rates, regressions, improvements, and rate deltas.
- Includes default benchmark suite replicating the 8 canonical tasks from upstream (`bench-001` through `bench-008`).
- Supports CLI flags: `--file`, `--json`, and `--compare <file_a> <file_b>`.
- Unit tested via `code/test_benchmark_runner.py` with 8 comprehensive test cases.

### 2.3 Supporting Templates
- `code/benchmark-comparison-template.md`: Template for comparing Harness A vs Harness B outcomes and cost deltas.
- `code/cleanup-loop.md`: Specification for recurring background cleanup tasks.
- `code/index.md`: Directory index describing the code components.

---

## 3. Test & Type Verification

Executed automated verification suite:
```bash
.venv/bin/mypy --config-file mypy.ini docs/harness-creator/lecture-12/code/
.venv/bin/ruff check docs/harness-creator/lecture-12/code/
.venv/bin/pytest docs/harness-creator/lecture-12/code/
```

### Verification Results:
- **Mypy**: `Success: no issues found in 4 source files`
- **Ruff**: `All checks passed!`
- **Pytest**: `22 passed in 0.14s` (13 cleanup scanner tests, 9 benchmark runner tests)

---

## 4. Repository Verification Matrix Audit

Audited `agent-skills-setup` against Lecture 12's 5 Invariants:
1. **Build & Type Checking**: Verified via `bash .claude/hooks/types-guard.sh` (whole-tree `mypy` passes clean).
2. **Automated Testing**: Verified via `bash scripts/run-tests.sh --fast` (all 73 test suites pass, 0 failures).
3. **State Layer Tracking**: Verified via `bash .claude/hooks/state-layer-guard.sh` (WIP=1 respected, completion evidence verified, schema valid).
4. **Clean Workspace & Stale Artifact Gap**: Audited against Invariant 4. While `runtime-drift-guard.sh` ensures `~/.agent-skills-setup` mirrors repo code and `secret-scan.sh` detects high-entropy credentials, automated detection of temporary files, WIP markers, and scratch scripts is currently an **open gap** in the repository's 10 verification gates. `cleanup_scanner.py` establishes the tool needed to close this gap.
5. **Startup Entrypoint**: Verified via `bash scripts/harness-verify.sh` (all 10 verification gates pass).

---

## 5. Artifact Summary

| File | Purpose | Status |
|---|---|---|
| `docs/harness-creator/lecture-12/code/cleanup_scanner.py` | Automated project debt & stale artifact scanner | Verified (13/13 tests, mypy clean) |
| `docs/harness-creator/lecture-12/code/test_cleanup_scanner.py` | Unit tests for cleanup scanner | Passing |
| `docs/harness-creator/lecture-12/code/benchmark_runner.py` | Repeatable benchmark slice runner & comparator | Verified (9/9 tests, mypy clean) |
| `docs/harness-creator/lecture-12/code/test_benchmark_runner.py` | Unit tests for benchmark runner | Passing |
| `docs/harness-creator/lecture-12/code/benchmark-comparison-template.md` | Harness A vs B comparison template | Authoritative |
| `docs/harness-creator/lecture-12/code/cleanup-loop.md` | Background cleanup loop specification | Authoritative |
| `docs/harness-creator/lecture-12/code/index.md` | Lecture 12 code folder index | Authoritative |
| `docs/harness-creator/lecture-12/summary.md` | Core lecture takeaways & analysis | Authoritative |
| `docs/harness-creator/lecture-12/progress-detail.md` | Detailed execution log & audit | Complete |
