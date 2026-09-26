# Harness Creator Training — Lecture 3: Why the Repository Must Become the System of Record

Source lecture: https://walkinglabs.github.io/learn-harness-engineering/en/lectures/lecture-03-why-the-repository-must-become-the-system-of-record/
Target repo: `agent-skills-setup` (this repo)
Date: 2026-09-26

---

## 1. Why This Exercise

Lecture 3 advances the harness engineering curriculum from the definition of a harness (Lecture 2: Instructions, Tools, Environment, State, Feedback) to the **System of Record** principle:
> *"Information that does not exist in the repository simply does not exist for the agent."*

Human engineers routinely rely on unwritten institutional knowledge, Slack threads, Jira tickets, and hallway conversations. For an autonomous AI agent, however, the working universe consists strictly of system prompts, tool outputs, and repository files. If an architectural boundary or state transition is not stored in the repository, the agent cannot access it, forcing it to guess.

This exercise audited `agent-skills-setup` using the diagnostic tools and assessment frameworks introduced in Lecture 3:
1. Running the automated discoverability diagnostic tool (`repo-reader.ts`).
2. Performing the **Fresh Session Test** (5 core project discoverability questions).
3. Quantifying the **Knowledge Visibility Gap** across project constraints.
4. Conducting an **ACID Assessment** of the harness's state management.

---

## 2. Automated Discoverability Diagnostic (`repo-reader.ts`)

The diagnostic script `repo-reader.ts` scores repository discoverability across 8 criteria (100 points maximum).

### 2.1 Baseline Audit (Before Remediations)
- **Score: 60 / 100 (60%) — Grade C (Partial structure, significant gaps)**
  - `AGENTS.md / CLAUDE.md`: PASS (15/15) — `AGENTS.md` exists at root.
  - `Documentation directory`: PASS (10/10) — `docs/` exists.
  - `Architecture documentation`: **FAIL (0/15)** — Missing `architecture.md`, `ARCHITECTURE.md`, or `docs/architecture.md`.
  - `Feature tracking`: PASS (15/15) — `feature_list.json` exists.
  - `Handoff / session continuity`: **FAIL (0/15)** — Lowercase `progress.md` failed standard scanner check expecting uppercase `PROGRESS.md` or `HANDOFF.md`.
  - `Testing structure`: PASS (10/10) — `tests/` directory present.
  - `Configuration files`: **FAIL (0/10)** — Missing standard project configuration manifest (`package.json`, `pyproject.toml`, `Cargo.toml`).
  - `README`: PASS (10/10) — `README.md` exists.

### 2.2 Remediations Applied
1. **Architecture Documentation (+15 pts):** Authored `docs/architecture.md` detailing system overview, subsystems (rules engine, skills registry, verification hooks, state management), directory layout, and hard architectural invariants. Recognized directly by `repo-reader.ts` without requiring a root symlink shim.
2. **Canonical Handoff / Session Continuity (+15 pts):** Upgraded `progress.md` directly to standard uppercase `PROGRESS.md` rather than a fragile symlink. Updated `state-layer-guard.sh` and its test suite to enforce `PROGRESS.md` (with backward compatibility fallback for `progress.md`).
3. **Configuration File (+10 pts):** Authored standard PEP 621 `pyproject.toml` specifying project metadata, Python `>=3.14` requirement, core dependencies, and dev extras.

### 2.3 Post-Remediation Audit
- **Score: 100 / 100 (100%) — Grade A (Repository is a strong system of record)**
- Zero symlinks at root, zero duplicate file entries, all 8 criteria passing clean.

---

## 3. Lecture 3 Exercises Summary

### Exercise 1: Fresh Session Test
Evaluated whether an agent with zero conversational context can answer the 5 canonical questions:
- **Q1 (What is this system?):** Answered immediately via `AGENTS.md`, `README.md`, and `docs/architecture.md`. Multi-agent skill setup and harness distribution engine.
- **Q2 (How is it organized?):** Answered via `docs/architecture.md` and `skills/README.md`. 4 primary layers: rules, skills, hooks, and state.
- **Q3 (How do I run it?):** Answered via `init.sh` and `scripts/install.sh`.
- **Q4 (How do I verify it?):** Answered via `scripts/harness-verify.sh` and `scripts/run-tests.sh`.
- **Q5 (Where are we now?):** Answered via `feature_list.json` (machine state) and `PROGRESS.md` (human/agent log).

### Exercise 2: Knowledge Externalization Quantification
Audited 20 essential development constraints and operational boundaries across the repository.
- 19 of 20 items were explicitly documented in repository files (`AGENTS.md`, `agents/engineering-rules.md`, `.claude/settings.json`, `docs/architecture.md`).
- Only 1 minor edge case remained implicit (temporary Docker daemon hang behavior during local `test_kiro_gateway.sh`).
- **Knowledge Visibility Gap:** 1 / 20 = **5.0%** (Well below the target threshold of <10%).

### Exercise 3: ACID Assessment
Evaluated repository state management against database transaction principles:
- **Atomicity:** Changes are staged and validated against all 8 gates before commit; hooks block partial completion.
- **Consistency:** `scripts/harness-verify.sh` and `state-layer-guard.sh` mechanically guarantee invariant validity.
- **Isolation:** Subagents and parallel tasks run in isolated git worktrees or temporary directories; tests isolate `$HOME`.
- **Durability:** All task states and decisions are committed to git-tracked files (`feature_list.json`, `PROGRESS.md`), persisting across session resets.

Full details and evidence logs: see [progress-detail.md](./progress-detail.md).
