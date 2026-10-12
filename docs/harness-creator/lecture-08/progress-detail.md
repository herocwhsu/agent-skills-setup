# Lecture 8 Training — Full Progress Detail

Companion to [summary.md](./summary.md). Date: 2026-10-09. Code artifacts in [code/](./code/).

---

## Step 0 — Baseline & Pre-checks

- Target repository: [`agent-skills-setup`](../../..)
- Commit: `8b0cd2d` (`feat-041`) on `main`
- Initial gate status: All 10 verification gates OK via `./init.sh`.
- Prior state:
  - Lecture 7 closed.
  - Initial Lecture 8 tooling ported to Python in `docs/harness-creator/lecture-08/code/`:
    - `feature_list_validator.py`
    - `test_feature_list_validator.py`
  - `state-layer-guard.sh` expanded to reject `done` features without evidence (27 tests passing in `test_state_layer_guard.sh`).

---

## Step 1 — Exercise 1: Feature List Primitive Validation

1. Executed unit tests for `feature_list_validator.py`:
   ```bash
   python3 -m pytest docs/harness-creator/lecture-08/code/test_feature_list_validator.py -v
   ```
   Output: 23 passed in 0.07s.
   Coverage:
   - Missing required keys (`id`, `name`, `description`, `status`)
   - Non-string or whitespace-only evidence for `status: "done"`
   - Non-string types in evidence (boolean, integer, dict, empty list)
   - Duplicate ID detection
   - Directory and file path loading

2. Executed validation on live repository `feature_list.json`:
   ```bash
   python3 docs/harness-creator/lecture-08/code/feature_list_validator.py feature_list.json
   ```
   Output: `41 features, valid`. Zero schema errors, zero unevidenced done features.

---

## Step 2 — Exercise 2: Verification Strictness Comparison

To quantify the difference between "loose" and "strict" verification, we evaluated three real repository features under deliberate behavioral mutations:

### Case 1: WIP=1 Limit Enforcement
- **Spec:** Only 1 feature can be active at a time.
- **Mutation:** Injected 2 concurrent active features (`{"status": "active"}`).
- **Loose check (`json.loads`):** Passed clean (exit 0). `json.loads` verifies only syntax structure. Result: **False positive (100% failure to detect violation)**.
- **Strict check (`scope_tracker.py` / `state-layer-guard.sh`):** Blocked with exit 2 (`WIP_ERROR: 2 features active concurrently`). Result: **Correctly rejected (0% false positive)**.

### Case 2: Case-Sensitive Filesystem Invariant
- **Spec:** Repository requires exact uppercase `PROGRESS.md` and rejects lowercase `progress.md`.
- **Mutation:** Created fixture with lowercase `progress.md` only.
- **Loose check (`bash -n` on guard script):** Passed clean (exit 0). Syntax validity of the guard script reveals nothing about whether the guard logic actually catches the casing regression. Result: **False positive (100%)**.
- **Strict check (`test_state_layer_guard.sh` Case 1b):** Directly asserts that running the hook on the fixture produces exit code 2. Result: **Correctly rejected (0% false positive)**.

### Case 3: Bash 3.2 Portability Guard
- **Spec:** Scripts must not use Bash 4+ features (`mapfile`, `declare -A`).
- **Mutation:** Script containing `mapfile` executed on macOS with modern Bash or default shellcheck.
- **Loose check:** Passed clean under Bash 5. Result: **False positive (100%)**.
- **Strict check (`test_bash_compat_guard.sh`):** Executes 15-case fixture matrix strictly under `/bin/bash` 3.2. Result: **Correctly rejected (0% false positive)**.

---

## Step 3 — Exercise 3: Single Source of Truth Principle Audit

We performed a repository-wide audit to identify scope discrepancies:
1. **Codebase Grep:** Scanned `scripts/`, `hooks/`, `skills/`, and documentation for unmanaged `TODO`, `FIXME`, or `HACK` comments. Result: Clean. No unmanaged development tasks hidden in code comments.
2. **State Artifact Divergence:**
   - `feature_list.json` held 41 completed features (`feat-001` through `feat-041`), all marked `done`.
   - `PROGRESS.md` held 6 queued technical items in `What's Next`.
   - **Diagnosis:** A machine scheduler reading `feature_list.json` sees an empty task backlog, whereas a human reading `PROGRESS.md` sees 6 items. This violates the Single Source of Truth principle.
3. **Resolution:**
   - Seeded `feature_list.json` with the highest-priority pending task (`feat-042`: Scope Stop gate tests to changed files) with `status: "not_started"`, `dependencies`, `acceptance_criteria`, and executable `verification` command.

---

## Step 4 — Verification

- Pytest validator suite: 23/23 passing.
- State layer guard: 27/27 passing.
- Harness verification: All 10 gates passed.
- No git commits created per user instructions (`no commit`).
