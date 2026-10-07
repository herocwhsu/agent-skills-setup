# Contributor Readiness Report: agent-skills-setup

This report documents the onboarding and readiness evaluation for a brand-new contributor in a fresh git clone at `/tmp/l6/ready-agy`. All actions were performed strictly using repository files and sandboxed with `HOME=/tmp/l6/home-b`. No modifications were made outside `/tmp/l6`, no commits were made, and forbidden installer scripts (`scripts/install.sh`, `install-agents-md.sh`, `init-repo.sh`, `setup-*.sh`) were not executed.

---

## 1. Numbered Steps with Outcomes

1. **Step 1: Read Repository Overview and Entry Documentation (`README.md`)**
   - *Action:* Examined `README.md` to identify project purpose and onboarding instructions.
   - *Outcome:* Identified project as `agent-skills-setup`. Noticed the "Quick Start" instructs running `bash scripts/install.sh`, `bash scripts/setup-credentials.sh`, and `bash scripts/setup-host.sh`. These are host-wide installation scripts rather than contributor development setup instructions. No virtual environment or local test instructions were found in `README.md`.

2. **Step 2: Read Contributor Working Rules and State Artifacts (`AGENTS.md`, `PROGRESS.md`, `feature_list.json`)**
   - *Action:* Examined `AGENTS.md`, `PROGRESS.md`, and `feature_list.json` per startup instructions.
   - *Outcome:* Identified canonical workflow: read `AGENTS.md`, check `feature_list.json` and `PROGRESS.md`, run `./init.sh` (which delegates to `scripts/harness-verify.sh`) before coding, and verify with `scripts/run-tests.sh --fast`.

3. **Step 3: Inspect Verification Entry Points (`init.sh`, `scripts/harness-verify.sh`, `scripts/run-tests.sh`)**
   - *Action:* Read `init.sh` and `scripts/harness-verify.sh` to understand verification gates.
   - *Outcome:* Confirmed `./init.sh` executes 10 gates via `.claude/hooks/*.sh`: registry, types, tests, skill paths, bash compat, cred backends, hook wiring, state layer, runtime drift, secret scan.

4. **Step 4: Check Python Version and Environment Requirements**
   - *Action:* Checked `.python-version`, system `python3`, and directory structure.
   - *Outcome:* Found `.python-version` pins `3.14.7`. Found system python3 is Python 3.14.7. Found that `.venv` did not exist in the clone (gitignored).

5. **Step 5: Run Initial Verification Gate (`./init.sh`)**
   - *Action:* Executed `HOME=/tmp/l6/home-b ./init.sh`.
   - *Outcome:* Verification **FAILED** (exit code 1).
     - `types` gate failed (exit 2): ambient `mypy` reported missing stub/module `anthropic` for `skills/utils/polish-input/lib/polish_engine.py`.
     - `tests` gate failed with 4 failing test scripts:
       - `test_precommit_sh_check.sh` (2 failures: `.agents/hooks.json` missing or precommit-sh-check not registered)
       - `test_py_check.sh` (1 failure: `.agents/hooks.json` registers PostToolUse py hook)
       - `test_sh_check.sh` (1 failure: `.agents/hooks.json` registers PostToolUse sh hook)
       - `test_stop_verify.sh` (2 failures: `.agents/hooks.json` registers Stop hook and timeout >= 600s)

6. **Step 6: Investigate Gate Failures and Git Status**
   - *Action:* Inspected `.agents/` directory, ran `git status`, and searched for `requirements-dev.txt` usage.
   - *Outcome:* Discovered two distinct root causes:
     - `.agents/hooks.json` was deleted in the working tree (`D .agents/hooks.json` in `git status`).
     - Ambient `mypy` was invoked because `.venv` did not exist; ambient Python lacked `anthropic`. The comment in `.claude/hooks/types-guard.sh` line 32 and `scripts/run-tests.sh` line 23 specified the required command: `python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt`.

7. **Step 7: Restore Missing Working Tree File (`.agents/hooks.json`)**
   - *Action:* Executed `HOME=/tmp/l6/home-b git checkout HEAD -- .agents/hooks.json`.
   - *Outcome:* `.agents/hooks.json` restored cleanly. `git status` confirmed working tree clean.

8. **Step 8: Set Up Contributor Development Environment (`.venv`)**
   - *Action:* Created `.venv` matching Python 3.14.7 via `HOME=/tmp/l6/home-b python3 -m venv .venv` and installed dependencies via `HOME=/tmp/l6/home-b .venv/bin/pip install -r requirements-dev.txt`.
   - *Outcome:* Virtual environment successfully created with all 43 packages in `requirements-dev.txt` (including `mypy==2.3.1`, `pytest==9.1.1`, `anthropic==1.6.0`, `google-genai==2.25.0`, `lxml==6.1.3`, `ruff==0.16.8`).

9. **Step 9: Run Test Suite (`bash scripts/run-tests.sh --fast`)**
   - *Action:* Executed `HOME=/tmp/l6/home-b bash scripts/run-tests.sh --fast`.
   - *Outcome:* **PASS** (62 test suites passed, 0 failed, 0 skipped, 0 untested code-bearing subcommands). This was Tool Call #33.

10. **Step 10: Run Full Verification Suite (`./init.sh`)**
    - *Action:* Executed `HOME=/tmp/l6/home-b ./init.sh`.
    - *Outcome:* **PASS** (exit code 0).
      - All 9 active verification gates passed: `registry`, `types`, `tests`, `skill paths`, `bash compat`, `cred backends`, `hook wiring`, `state layer`, `secret scan`.
      - `runtime drift` reported `SKIP` as expected (runtime not installed at `/tmp/l6/home-b/.agent-skills-setup`).

---

## 2. Problems Hit with Severity & Responsible Documentation

| # | Problem Hit | Severity | Which Doc Should Have Told You | Description / Impact |
|---|---|---|---|---|
| 1 | **README instructs running host-wide install scripts** | Blocker / Slowdown | `README.md` | `README.md` lines 32–44 under "Quick Start" instructs running `bash scripts/install.sh`, `bash scripts/setup-credentials.sh`, and `bash scripts/setup-host.sh`. In sandboxed contributor development, these modify user-level home directories (`~/.claude`, `~/.codex`, etc.) and are prohibited. `README.md` lacks a dedicated "Development Setup" section for contributors working on the repository itself. |
| 2 | **Missing local development environment setup instructions** | Blocker | `README.md` / `AGENTS.md` | Neither `README.md` nor `AGENTS.md` documents how to initialize `.venv` from `requirements-dev.txt`. The command `python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt` was only discovered inside error strings in `.claude/hooks/types-guard.sh` (line 32) and `scripts/run-tests.sh` (line 23), plus historical lecture notes (`docs/harness-creator/lecture-02/summary.md`). |
| 3 | **Fresh clone fails `types` gate on ambient `mypy` fallback** | Blocker | `AGENTS.md` / `README.md` | When `.venv` is missing, `types-guard.sh` falls back to ambient `mypy`. On systems where ambient python lacks `anthropic`, `types-guard.sh` fails with `Cannot find implementation or library stub for module named "anthropic"`, blocking `./init.sh`. A new contributor running `./init.sh` out of the box immediately fails. |
| 4 | **Tracked file `.agents/hooks.json` missing/deleted in working tree** | Blocker | Working tree / clone state | `git status` revealed `.agents/hooks.json` was deleted in the working tree, causing 4 hook tests (`test_precommit_sh_check.sh`, `test_py_check.sh`, `test_sh_check.sh`, `test_stop_verify.sh`) to fail. Required running `git checkout HEAD -- .agents/hooks.json` to restore. |
| 5 | **`AGENTS.md` assumes `.venv` already exists** | Slowdown | `AGENTS.md` | `AGENTS.md` line 74 instructs: `Run mypy over the whole repo via .venv/bin/mypy . (never per single file)`, but provides no prerequisite step or check for creating `.venv`. |

---

## 3. Required Answers with Source Files

### How to Run
- **Answer:**
  This repository is `agent-skills-setup`, a multi-agent toolkit providing slash commands, skills, and lifecycle hooks across Claude Code, Antigravity CLI (agy), Codex CLI, and Kiro.
  - To run outside agent routing / queries: `bash scripts/outside-agent.sh run [--purpose review] "<prompt>"`
  - To run credential management: `bash scripts/credentials/service.sh list`
  - To verify the repository state: `./init.sh` (delegates to `bash scripts/harness-verify.sh`)
  - To initialize OpenSpec in a project: `openspec init` followed by `openspec update`
- **Source Files:**
  - `README.md` (lines 1–17, 32–44, 73–91)
  - `docs/architecture.md`
  - `scripts/outside-agent.sh`
  - `init.sh`

### How to Test
- **Answer:**
  - Fast test suite (skipping integration tests): `bash scripts/run-tests.sh --fast`
  - Full test suite (including integration tests): `RUN_INTEGRATION=1 bash scripts/run-tests.sh`
  - Canonical full verification (runs registry guard, types guard, test suite, skill paths guard, bash compat guard, cred backends guard, hook wiring guard, state layer guard, runtime drift guard, and secret scan): `bash scripts/harness-verify.sh` (or `./init.sh`)
- **Source Files:**
  - `AGENTS.md` (lines 25–32)
  - `scripts/run-tests.sh` (lines 1–114)
  - `scripts/harness-verify.sh` (lines 1–85)
  - `init.sh` (lines 1–11)

### Current State
- **Answer:**
  - Active feature: None (`feat-034`, `feat-035`, and `feat-036` are closed out and marked `done`).
  - All 9 active verification gates pass clean (registry, types, tests, skill paths, bash compat, cred backends, hook wiring, state layer, secret scan). The `runtime drift` gate cleanly skips when the runtime is not installed in the active `$HOME`.
  - Fast test suite: 62 passed, 0 failed, 0 skipped, 0 untested code-bearing subcommands.
  - Completed feature highlights:
    - `feat-035`: `outside-agent.sh` runner and Outside agents rule.
    - `feat-036`: Two-reviewer rule, branch cleanup rule, README outside-agent flow charts, and repo-wide cleanup.
- **Source Files:**
  - `PROGRESS.md` (lines 3–10, 160–163)
  - `feature_list.json` (features `feat-035` and `feat-036`, lines 273–290)

### Next Task
- **Answer:**
  The next planned items listed in `PROGRESS.md` are:
  1. Re-run the `codex-kiro` and `agy` smoke test live against the `feat-033` fixes; trust the repo hooks in Codex on each host.
  2. Optional: Scope the Stop gate's tests to changed files so a stop no longer takes ~3 minutes.
  3. Run the fresh-session test again on the real `hangar` and `atelier` `main` (`kiro-cli` and `gemini` `AGENTS.md` support is still untested: neither is logged in headless).
  4. Optional follow-up experiment: Repeat exercise 3 at ~10k tokens without the "read in full" instruction (design in `docs/harness-creator/lecture-04/position-experiment.md` §13).
  5. Lecture 6: Why Initialization Needs Its Own Phase.
- **Source Files:**
  - `PROGRESS.md` (lines 164–173)

---

## 4. Tool Call Accounting

- **Total tool calls in session:** 36
- **Call number of first passing test:** Call #33 (`run_command`: `HOME=/tmp/l6/home-b bash scripts/run-tests.sh --fast`, which resulted in 62 passed, 0 failed).
