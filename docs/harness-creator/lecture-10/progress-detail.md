# Lecture 10 Training — Full Progress Detail

Companion to [summary.md](./summary.md). Date: 2026-10-09. Code artifacts in [code/](./code/).

---

## Step 0 — Baseline & Pre-checks

- Target repository: [`agent-skills-setup`](file:///Users/phoenix/projects/agent-skills-setup)
- Commit: `f43ab92` on `main` (Lecture 09 closed and verified).
- Initial gate status: All 10 gates passed via `scripts/harness-verify.sh`.
- Fast tests: 67 passed, 0 failed.
- Features tracked: 42 features in `feature_list.json` (41 done, 1 not_started).

---

## Step 1 — Exercise 1: Cross-Component Defect Detection

We implemented [`code/e2e_runner.py`](./code/e2e_runner.py) to simulate and analyze the disparity between isolated unit test execution and complete pipeline integration.

### Test Scenarios Analyzed:

1. **Document Ingestion & Citations**:
   - *Flow*: Parse $\to$ Store Chunks $\to$ Index Vectors $\to$ Retrieve Chunks $\to$ Generate Citations.
   - *Unit Tests*: 5/5 passed. Each component mocked the input/output schema of adjacent components.
   - *E2E Reality*: Fails at Step 4 (Retrieve). Indexer used 768-dim embeddings while retriever queried against 1536-dim vector space.
   - *Defect Category*: **Interface Mismatch** (Schema/Protocol incompatibility between modules).

2. **Document Deletion & Cache Cleanup**:
   - *Flow*: Find Doc ID $\to$ Delete Doc Record $\to$ Remove Indexed Chunks $\to$ Verify Clean Search.
   - *Unit Tests*: 4/4 passed. Database deletion unit test verified SQL `DELETE`; search unit test used mock in-memory index.
   - *E2E Reality*: Fails at Step 3 (Remove Indexed Chunks). Background deletion timeout left orphaned chunks; subsequent search queries leaked deleted documents.
   - *Defect Category*: **State Propagation Inconsistency** (Asynchronous cross-store state drift).

3. **Multi-User Concurrent Access**:
   - *Flow*: User A Import $\to$ User B Import $\to$ User A Query $\to$ Verify Tenant Isolation.
   - *Unit Tests*: 4/4 passed. All unit tests ran single-user test cases against fresh database connections.
   - *E2E Reality*: Fails at Step 4 (Verify Isolation). In-memory query cache lacked tenant ID prefix, leaking User B's documents into User A's response.
   - *Defect Category*: **Cross-Tenant Isolation Failure** (Concurrency/Environment discrepancy).

4. **Healthy Single-Component Flow**:
   - *Flow*: Sanitize $\to$ Transform $\to$ Emit Event.
   - *Unit Tests*: 3/3 passed.
   - *E2E Reality*: 3/3 passed. Both layers concordant.

### Execution Metrics:
- Total Scenarios: 4
- False Confidence Cases (Unit PASS but E2E FAIL): 3
- **False Confidence Rate**: **75.0%**

---

## Step 2 — Exercise 2: Architectural Rule Automation

To prevent agents from violating repository design principles, rules cannot remain passive documentation. They must be compiled into executable harness checks equipped with **Agent-Oriented Error Messages** containing:
1. `WHAT`: Precise filename, line number, and violation description.
2. `WHY`: Architectural context and rationale.
3. `HOW (FIX)`: Concrete, copy-pasteable remediation instructions.

### Three Repository Architectural Rules Automated in `agent-skills-setup`:

1. **Rule: Shell Script Backward Compatibility**:
   - *Constraint*: All shell scripts in `.claude/hooks/` and `scripts/` must be compatible with macOS `/bin/bash` 3.2.
   - *Enforcement Script*: `.claude/hooks/bash-compat-guard.sh`
   - *Agent Diagnostic*:
     ```text
     ERROR: Incompatible Bash 4+ construct 'declare -A' in .claude/hooks/my-guard.sh:22
     WHY: macOS default shell is Bash 3.2. Associative arrays and mapfile cause fatal syntax errors on macOS.
     FIX: Use indexed arrays, flat key_value variables, or delegate dictionary logic to python3.
     ```

2. **Rule: Single Source of Truth & Evidence Gate**:
   - *Constraint*: Every completed feature in `feature_list.json` must provide non-empty execution evidence; `PROGRESS.md` must be uppercase.
   - *Enforcement Script*: `.claude/hooks/state-layer-guard.sh` and `feature_list_validator.py`
   - *Agent Diagnostic*:
     ```text
     ERROR: Feature 'feat-042' has status 'done' but 'evidence' is empty or invalid.
     WHY: Repository integrity requires verifiable test output to prevent unverified completion declarations.
     FIX: Run 'bash scripts/run-tests.sh --fast', copy the result summary into 'evidence', and re-run.
     ```

3. **Rule: Turn-Scope Read Permission Safety**:
   - *Constraint*: Agent read operations (`git log`, `git diff`, `cat`, `view_file`) must execute unprompted without interactive confirmation blocks.
   - *Enforcement Script*: `.claude/settings.json` permissions allowlist and PreInvocation guards.
   - *Agent Diagnostic*:
     ```text
     ERROR: Read tool blocked on permission prompt for 'git log'.
     WHY: Interactive prompts disrupt headless subagent execution loops.
     FIX: Add command prefix 'git log' to allowed commands in agent settings.
     ```

---

## Step 3 — Exercise 3: Review Feedback Promotion

We traced the lineage of critical rules in this repository to verify that human/subagent review comments systematically become permanent harness tests:

| Originating Feature / Incident | Review Comment / Finding | Promoted Harness Gate | Outcome |
|---|---|---|---|
| **feat-002** (Trailers) | "Claude Code automatically adds Co-Authored-By trailers to git commits." | Repo-level `.claude/settings.json` configuring `attribution.commit=""`. | 100% elimination of attribution trailers repo-wide. |
| **feat-032** (YAML Syntax) | "AGY fails to load apidog and progress skills due to unquoted colon in YAML description." | `scripts/skill-frontmatter-check.py` integrated into `skill-paths-guard.sh`. | Automated blocking of invalid YAML frontmatter before commit. |
| **feat-040** (WIP Creep) | "Subagents start multiple features at once and claim completion without tests." | `state-layer-guard.sh` asserting `active <= 1` and evidence presence. | Mechanically blocked multi-task overreach. |
| **feat-041** (Case Drift) | "Mac filesystems are case-insensitive by default, causing lowercase progress.md bugs on Linux." | Inverted `state-layer-guard.sh` case check; codified case-sensitive invariant in `PROGRESS.md`. | Rejection of lowercase progress files across all platforms. |
| **Lecture 09 Audit** | "AGY Stop hook in .agents/hooks.json fails with exit 127 due to `cd ..` jumping outside repo." | Removed `cd ..` from `.agents/hooks.json`, executing cleanly from repo root. | 78/78 hook tests pass across all agents. |

---

## Step 4 — Verification

### Unit Test Execution:
```bash
.venv/bin/pytest docs/harness-creator/lecture-10/code/test_e2e_runner.py
```
Output:
```text
============================== 5 passed in 0.04s ===============================
```

### Full Fast Suite:
```bash
bash scripts/run-tests.sh --fast
```
Output:
- Script tests: 33 passed
- Lecture tests: 5 passed (including `test_e2e_runner.py`)
- Skill tests: 29 passed
- Coverage check: 0 missing
- Total: **68 passed, 0 failed, 0 skipped**.

### Harness Verification:
```bash
bash scripts/harness-verify.sh
```
Output:
- All 10 gates passed clean (`registry`, `types`, `tests`, `skill paths`, `bash compat`, `cred backends`, `hook wiring`, `state layer`, `runtime drift`, `secret scan`).
