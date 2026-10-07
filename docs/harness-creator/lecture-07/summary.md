# Harness Creator Training — Lecture 7: Why Agents Overreach and Under-finish

Source lecture: https://walkinglabs.github.io/learn-harness-engineering/en/lectures/lecture-07-why-agents-overreach-and-under-finish/  
Target repo: `agent-skills-setup`  
Date: 2026-10-07. Full log: [progress-detail.md](./progress-detail.md). Raw reports: [raw/](./raw/).  

---

## 1. What the Lecture Claims

Agents possess an inherent impulse to "do a little extra" — refactoring adjacent code, jumping ahead to unrequested features, or starting multiple items at once. Because context capacity $C$ and attention are strictly finite, activating $k$ features dilutes available reasoning to $C/k$. When $C/k$ falls below the minimum required for rigorous verification, all $k$ items become half-implemented:
- **Overreach:** Activating more tasks in a session than optimal.
- **Under-finish:** Ratio of tasks that pass end-to-end verification falls below acceptable thresholds.
- **The Solution:** Enforce strict **WIP=1** (Work-in-Progress = 1), require **executable completion evidence** before unlocking subsequent tasks, and externalize the scope surface in a machine-verifiable state artifact.

---

## 2. What We Measured

| Exercise | Setup | Result |
|---|---|---|
| **1. Task Atomization** | Backlog requirement: "Scoped test execution for Stop gate" (`PROGRESS.md:172`) | Broken into 5 atomic DAG units with executable verification commands and WIP=1 allowed-path boundaries ([plan](code/task-atomization-plan.md)). |
| **2. Comparison Experiment** | `kvstore` CLI in `/tmp/l7/exp-a` (unconstrained) vs. `/tmp/l7/exp-b` (WIP=1 enforced). 10-call budget. Independent grading by `hidden_accept.py`. | **86 vs. 125 LOC (-31% code bloat)** under WIP=1. Both scored 5/5 on hidden acceptance, but unconstrained added unsolicited features (`argparse` subparsers, environment overrides, fallback flags). |
| **3. Completion Evidence Audit** | Audit `feature_list.json` and `PROGRESS.md` against WIP=1 and executable verification. | Closed Lecture 6 open items: added WIP=1 & evidence verification to `.claude/hooks/state-layer-guard.sh` (17/17 passed) and ordered `What's Next` into prioritized queue with verification commands. |

### 2.1 Exercise 2: Comparison Experiment Results

Both conditions were tested against an independent 5-check test suite (`/tmp/l7/testsuite/hidden_accept.py`):

| Metric | Condition A (Unconstrained) | Condition B (WIP=1 Enforced) |
|---|:---:|:---:|
| Features Activated | 5 (all simultaneously) | 5 (strictly sequential F1→F2→F3→F4→F5) |
| Hidden Acceptance Score | 5 / 5 (100%) | 5 / 5 (100%) |
| Verified Completion Rate (VCR) | 1.0 | 1.0 |
| Implementation Lines of Code | **125 lines** | **86 lines (-31.2%)** |
| Extraneous Scope / Spec Bloat | Yes: `argparse`, `KV_STORE_PATH`, unrequested positional args, polymorphic value handling | None: minimal stdlib implementation matching exact spec |
| Test Organization | Single monolithic file (`test_kvstore.py`) | Granular per-feature unit tests (`test_f1.py` ... `test_f5.py`) |

> **Key Finding:** Unconstrained prompting induces scope inflation and architectural over-engineering even on simple requirements. WIP=1 keeps the model's attention focused on the immediate task, producing surgical code that satisfies verification with significantly less dead weight.

---

## 3. Harness Remediations Applied to `agent-skills-setup`

1. **State Layer Guard Enforcement (`state-layer-guard.sh`):**
   - Upgraded `.claude/hooks/state-layer-guard.sh` to mechanically enforce:
     - **WIP Limit:** Blocks with `exit 2` if more than one feature is in `active` / `in_progress` status.
     - **Completion Evidence:** Blocks with `exit 2` if an active feature lacks a non-empty `verification` or `acceptance_criteria` command.
   - Added unit test cases 8, 9, and 10 to `.claude/hooks/tests/test_state_layer_guard.sh` (17/17 passing clean).
2. **State Layer Audit Tooling (`docs/harness-creator/lecture-07/code/scope_tracker.py`):**
   - Standalone CLI to audit `feature_list.json` and working-tree git status against active scope boundaries.
3. **`AGENTS.md` Startup Workflow:**
   - Explicitly codified Step 5 in `Startup Workflow`: enforce WIP=1 (one feature at a time, no simultaneous feature activations or unsolicited refactorings).
4. **Resolved Lecture 6 Open Items:**
   - Restructured `PROGRESS.md`'s `What's Next` from an unordered prose bullet list into an ordered, prioritized queue with explicit verification commands and blocked/ready states.

---

## 4. Verification

- `bash .claude/hooks/tests/test_state_layer_guard.sh`: 17 passed, 0 failed.
- `python3 docs/harness-creator/lecture-07/code/test_scope_tracker.py`: All passed.
- `bash .claude/hooks/bash-compat-guard.sh`: Clean (macOS bash 3.2 portable).
- `bash scripts/tests/test_engineering_rules_scope.sh`: 12/12 passed.
- `python3 /tmp/l7/testsuite/hidden_accept.py /tmp/l7/exp-b`: 5/5 passed.

---

## 5. Status

**Lecture 7 is closed.**
- Working tree modifications remain uncommitted per user instruction (`not commit`).
- Open items from Lecture 6 (`What's Next` ordering and executable verification criteria) are formally resolved.
