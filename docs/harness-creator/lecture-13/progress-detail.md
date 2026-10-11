# Lecture 13 Detailed Execution Log

**Date:** 2026-10-11  
**Focus:** From Manual Prompting to Autonomous Loops (Loop Engineering, Generator/Evaluator Separation, Karpathy's autoresearch Ratchet Loop, Six Primitives, Four Silent Costs).  
**Repository:** `agent-skills-setup`  
**Related summary:** [summary.md](./summary.md)  
**Code artifacts:** [code/](./code/)

---

## 1. Objectives & Context

Lecture 13 marks the shift from human-in-the-loop manual prompting (Lectures 1–12) to autonomous loop systems (Loop Engineering):
1. **Inside vs. Outside the Loop**:
   - The human stops being the step-by-step scheduler and becomes the loop designer.
   - Core shift: defining goals, verification commands, and stopping conditions upfront, then reviewing landing inboxes.
2. **The Six Primitives of a Loop**:
   - Automations (triggers), Worktrees (isolation), Skills (knowledge), Connectors (MCP), Sub-agents (Maker/Checker split), External State (disk memory).
3. **Generator/Evaluator Separation**:
   - Eliminating the self-evaluation paradox by isolating the agent that implements from the agent that verifies.
4. **The Nine-Step Ratchet Cycle**:
   - Inspired by Karpathy's `autoresearch`: hypothesize → edit → snapshot → train/test → evaluate → keep if improved or rollback (`git reset`) if degraded.
5. **Circuit Breakers & Four Silent Costs**:
   - Safeguarding against verification debt, comprehension rot, cognitive surrender, and token blowout via deterministic stopping conditions (`max_rounds`, `max_consecutive_failures`, metric thresholds).

---

## 2. Ported Code Artifacts

### 2.1 Autonomous Ratchet Loop Engine (`code/ratchet_loop.py`)
- Python 3.9–3.14 compatible, strongly typed implementation of the 9-step ratchet cycle.
- Core classes & functions:
  - `LoopGoal`: Structured specification parsed from Markdown (`parse_goal_markdown`), including acceptance criteria, fair-game and hands-off scope boundaries, and verification commands.
  - `RoundLog` & `LoopState`: Persistent state tracking with cumulative statistics (rounds completed, kept improvements, reverted attempts, issues found, blockers).
  - `RatchetLoopRunner`: Executes iterative rounds, evaluates metric improvements (supports both minimization and maximization), runs multi-command verification, coordinates Maker implementation and independent Checker evaluation, and triggers automated rollbacks upon regression.
  - Circuit breakers: Halts loop when target threshold is reached (`COMPLETED`), when consecutive failures exceed budget (`BLOCKED`), or when round budget is exhausted (`MAX_ROUNDS_REACHED`).
  - Disk-persisted state: Generates human-readable Markdown dashboard (`render_state_markdown`) and append-only TSV experiment logs (`results.tsv`).
- CLI interface: `--demo` mode running synthetic optimization cycles, `--goal-file`, `--state-file`, `--tsv-file`.

### 2.2 Test Suite (`code/test_ratchet_loop.py`)
- 7 comprehensive unit test cases verifying:
  - `test_parse_goal_markdown`: Markdown parsing of goal metadata, criteria, commands, and scopes.
  - `test_is_improvement`: Metric evaluation for lower-is-better and higher-is-better.
  - `test_verification_command_execution`: Execution and failure handling of shell verification commands.
  - `test_execute_round_ratchet_decisions`: Proper KEEP and REVERT branching, best metric tracking, consecutive failure counting, and rollback invocation.
  - `test_target_completion_threshold`: Automated completion when target metric threshold is satisfied.
  - `test_max_rounds_circuit_breaker`: Halting when max rounds budget is reached.
  - `test_state_persistence_and_markdown`: Disk serialization to Markdown and TSV format.

### 2.3 Supporting Templates
- `code/goal-template.md`: Template for writing `/goal` specifications with fair-game and hands-off scopes.
- `code/maker-prompt.md`: Instructions for implementation agents.
- `code/checker-prompt.md`: Instructions for independent verification checkers.
- `code/loop-state-template.md`: Template for disk-based loop memory tracking.
- `code/index.md`: Directory index describing the code components.

---

## 3. Test & Type Verification

- **Linting & Code Style:**
  ```bash
  .venv/bin/ruff check docs/harness-creator/lecture-13/code/
  # Output: All checks passed!
  ```
- **Type Checking:**
  ```bash
  .venv/bin/mypy --config-file mypy.ini docs/harness-creator/lecture-13/code/
  # Output: Success: no issues found in 2 source files
  ```
- **Unit Tests:**
  ```bash
  .venv/bin/pytest docs/harness-creator/lecture-13/code/test_ratchet_loop.py
  # Output: 7 passed in 0.20s
  ```
- **macOS System Python 3.9 Compatibility:**
  ```bash
  /usr/bin/python3 docs/harness-creator/lecture-13/code/ratchet_loop.py --demo
  # Output: 4 rounds completed, rollback verified, status COMPLETED
  ```
