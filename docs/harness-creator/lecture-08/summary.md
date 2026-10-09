# Harness Creator Training — Lecture 8: Why Feature Lists Are Harness Primitives

Source lecture: https://walkinglabs.github.io/learn-harness-engineering/en/lectures/lecture-08-why-feature-lists-are-harness-primitives/  
Target repo: `agent-skills-setup`  
Date: 2026-10-09. Full log: [progress-detail.md](./progress-detail.md). Code: [code/](./code/).

---

## 1. What the Lecture Claims

A feature list is not an optional planning memo for humans; it is a **foundational harness primitive** that all other harness components depend on:
1. **The Scheduler** reads feature states to pick the next unblocked `not_started` item.
2. **The Verifier** executes explicit verification commands and controls state transitions (`not_started` $\to$ `active` $\to$ `passing` $\to$ `done`).
3. **The Handoff Reporter** compiles progress from versioned machine state rather than conversational inference.

### The Triple Structure
Every feature item must satisfy the triple:
$$\text{Feature} = (\text{Behavior Description}, \text{Verification Command}, \text{Current State})$$
Without this triple, the agent falls back to its implicit default: *"the code has no syntax errors and looks fairly complete."*

---

## 2. What We Measured

| Exercise | Setup | Result |
|---|---|---|
| **1. Feature List Validation** | Evaluated [`code/feature_list_validator.py`](./code/feature_list_validator.py) (ported from upstream TS) across 23 unit test cases and real [`feature_list.json`](../../../feature_list.json). | **41 features valid** (23/23 tests pass). Verified that missing fields, duplicate IDs, whitespace evidence, and done-without-evidence are mechanically blocked. |
| **2. Verification Strictness Comparison** | Evaluated "loose" (syntax/exit code only) vs. "strict" (behavioral mutation) verification across 3 core features (WIP limit, Case sensitivity, Bash 3.2 compat). | **Loose verification had a 100% false positive rate** under mutation, allowing broken states (e.g. WIP=2, Bash 4 constructs) to pass green. Strict behavioral verification had **0% false positive rate**. |
| **3. Single Source Principle Audit** | Audited repo for unexternalized backlog items and code TODOs across `PROGRESS.md`, source trees, and `feature_list.json`. | Zero code TODOs found. Surfaced a structural gap: `feature_list.json` held only completed features (41/41 done), while queued work lived as prose in `PROGRESS.md`, creating a split source of truth. |

---

## 3. Findings from Exercise 2: Verification Strictness Comparison

| Feature Under Test | Loose Check | Strict Check | False Positive Rate (Loose) |
|---|---|---|:---:|
| **WIP=1 Limit Enforcement** (`feat-040`) | Valid JSON parse (`json.loads`) | State machine validation (`scope_tracker.py` / `feature_list_validator.py`) | **100%** (Accepts WIP > 1) |
| **Case-Sensitive State Guard** (`feat-041`) | Syntax check (`bash -n`) | Fixture assertion asserting exit 2 on lowercase `progress.md` | **100%** (Accepts lowercase regression) |
| **Bash 3.2 Portability Guard** (`feat-016`) | Modern system syntax check / default shellcheck | 15-case fixture matrix evaluated under `/bin/bash` 3.2 | **100%** (Accepts `mapfile` / `declare -A`) |

> **Key Finding:** "Loose" verifications (compilation, syntax validity, exit code 0) create an illusion of correctness. Under behavioral mutations, loose checks pass 100% of the time, allowing silent regressions to enter the repository. Strict verifications assert business logic invariants and error paths.

---

## 4. Single Source of Truth Resolution

The audit in Exercise 3 revealed that:
1. All past work (41 features) is externalized and verified in `feature_list.json`.
2. However, future technical tasks existed only as Markdown bullets in `PROGRESS.md`'s *What's Next*. An automated scheduler inspecting `feature_list.json` alone would conclude that the project is 100% finished.
3. **Resolution:** High-priority items from `PROGRESS.md`'s technical queue will be registered directly in `feature_list.json` with `status: "not_started"`, explicit `acceptance_criteria`, and executable `verification` commands, restoring `feature_list.json` as the single machine-readable authority.

---

## 5. Verification

- `python3 -m pytest docs/harness-creator/lecture-08/code/test_feature_list_validator.py`: 23 passed in 0.07s.
- `python3 docs/harness-creator/lecture-08/code/feature_list_validator.py feature_list.json`: 41 features, valid.
- `bash .claude/hooks/tests/test_state_layer_guard.sh`: 27 passed, 0 failed.
- `bash scripts/harness-verify.sh`: All gates passed.

---

## 6. Status

**Lecture 8 is closed.**
- All documentation, experiment logs, and validator tooling are verified.
- Working tree remains completely uncommitted per user instruction (`no commit`).
