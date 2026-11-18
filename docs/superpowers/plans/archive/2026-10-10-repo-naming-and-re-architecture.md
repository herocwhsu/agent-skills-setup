# Repository Naming Standardization & Folder Re-Architecture Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardize file naming conventions (enforcing PEP 8 `snake_case` across all Python engines and `kebab-case` across shell utilities) and re-architect directory structure to eliminate root clutter, disambiguate active hooks from template libraries, and preserve 100% backward compatibility with multi-agent runtimes.

**Architecture:** Maintain strict surgical boundaries by separating user-facing CLI entrypoints from internal verification engines, isolating target-project template libraries under `templates/`, co-locating agent-specific assets under `config/` or `agents/`, and maintaining full compatibility with the 11 harness gates and SLA benchmarks.

**Tech Stack:** Bash 3.2, Python 3.14.7, pytest, mypy, ruff, jq, git.

**Spec:** Current codebase investigation across `.claude/hooks/`, `scripts/`, `hooks/`, `skills/`, and `benchmarks/`.

---

## Global Constraints

- **Bash 3.2 Floor:** All shell scripts must remain strictly compatible with macOS `/bin/bash` 3.2 (no Bash 4/5 constructs, no `declare -A`, no `mapfile`).
- **PEP 8 Compliance:** All Python files must use lowercase `snake_case.py` (no hyphens), enabling standard Python `import` statements and linters.
- **WIP=1 Integrity:** Exactly one feature active at a time in `feature_list.json` and `PROGRESS.md`.
- **Zero Runtime Drift:** Any modification to files listed in `runtime_files()` (`scripts/_lib.sh`) must be synchronized to `~/.agent-skills-setup` so `runtime-drift-guard.sh` passes.
- **Git Push Prohibition:** Never execute `git push` without explicit user instruction.
- **Verification Gate Integrity:** All 11 gates in `scripts/harness-verify.sh` must pass cleanly (exit 0) at every task milestone.

---

## Review Focus & Failure Modes

1. **Broken Hook Call Sites:** Renaming internal Python scripts (`credential-backend-check.py` -> `credential_backend_check.py`) must update all guard hook scripts; otherwise `.claude/hooks/*-guard.sh` will fail with exit 2.
2. **Runtime Drift Discrepancy:** Moving or renaming files registered in `runtime_files()` (`lib.sh`, `outside_agent.py`, etc.) without updating `scripts/_lib.sh` will cause Gate 10 (`runtime-drift-guard.sh`) to fail.
3. **External Project Template Breakage:** Renaming `hooks/` templates must update `scripts/init-repo.sh`, `scripts/tests/test_init_repo.sh`, and `docs/harness-adoption.md`.
4. **Targeted Test Resolution Desync:** Any file rename must update `scripts/resolve_test_targets.py` to ensure `--changed` correctly maps modified files to their respective tests.
5. **Kiro Prompt Installation Breakage:** Relocating `prompts/` must update `install_kiro_prompts()` and `uninstall_kiro_prompts()` in `scripts/_lib.sh`.

---

## Detailed Audit: Current State vs Proposed Target

### 1. Naming Inconsistencies Identified

| Current Path | Type | Issue | Proposed Standard Path |
| :--- | :--- | :--- | :--- |
| `scripts/credential-backend-check.py` | Python Script | Hyphenated filename (violates PEP 8, cannot be imported) | `scripts/credential_backend_check.py` |
| `scripts/hook-wiring-check.py` | Python Script | Hyphenated filename (violates PEP 8, cannot be imported) | `scripts/hook_wiring_check.py` |
| `scripts/skill-frontmatter-check.py` | Python Script | Hyphenated filename (violates PEP 8, cannot be imported) | `scripts/skill_frontmatter_check.py` |
| `scripts/skill-path-var-check.py` | Python Script | Hyphenated filename (violates PEP 8, cannot be imported) | `scripts/skill_path_var_check.py` |
| `scripts/apidog-share-fetch.py` | Python Script | Hyphenated filename (violates PEP 8, cannot be imported) | `scripts/apidog_share_fetch.py` |
| `scripts/outside_agent.py` | Python Script | PEP 8 snake_case | Retain (paired with `scripts/outside-agent.sh`) |
| `scripts/harness_benchmark.py` | Python Script | PEP 8 snake_case | Retain (paired with `scripts/harness-benchmark.sh`) |
| `scripts/resolve_test_targets.py` | Python Script | PEP 8 snake_case | Retain |

### 2. Directory Layout Inconsistencies & Re-Architecture

| Current Path | Purpose | Architectural Smell | Proposed Target Layout |
| :--- | :--- | :--- | :--- |
| `hooks/` | Template library for target projects | Confused with active repo hooks in `.claude/hooks/` | `templates/hooks/` (with clean backward-compatible fallback) |
| `prompts/` | 15 Markdown prompt templates for Kiro IDE | Top-level root directory clutter; agent-specific | `config/kiro/prompts/` or `agents/kiro/prompts/` |
| `lib/lib.sh` | Shared runtime helper copied to `~/.agent-skills-setup/` | Standalone root folder containing only 1 file | `lib/` can be maintained or consolidated under `runtime/` |
| `scripts/` | 32 files mixing CLI tools, setup scripts, and internal checkers | Flat directory sprawl | Keep CLI entrypoints top-level in `scripts/`; internal helpers standardized |

---

## Tasks

### Task 1: Python Module Naming Standardization (PEP 8 Compliance)
**Files:**
- Rename: `scripts/credential-backend-check.py` -> `scripts/credential_backend_check.py`
- Rename: `scripts/hook-wiring-check.py` -> `scripts/hook_wiring_check.py`
- Rename: `scripts/skill-frontmatter-check.py` -> `scripts/skill_frontmatter_check.py`
- Rename: `scripts/skill-path-var-check.py` -> `scripts/skill_path_var_check.py`
- Rename: `scripts/apidog-share-fetch.py` -> `scripts/apidog_share_fetch.py`
- Modify: `.claude/hooks/credential-backend-guard.sh`
- Modify: `.claude/hooks/skill-paths-guard.sh`
- Modify: `scripts/harness-verify.sh`
- Modify: `scripts/resolve_test_targets.py`
- Modify: `scripts/tests/test_apidog_share_fetch.sh`
- Modify: `scripts/tests/test_hook_wiring.sh`
- Modify: `scripts/tests/test_skill_paths_guard.sh`
- Modify: `scripts/tests/test_credential_backend_guard.sh`
- Modify: `benchmarks/harness-suite.json`

**Steps:**
- [ ] Git mv each of the 5 Python files to their snake_case names.
- [ ] Update invocations in `.claude/hooks/credential-backend-guard.sh`.
- [ ] Update invocations in `.claude/hooks/skill-paths-guard.sh`.
- [ ] Update invocations in `scripts/harness-verify.sh`.
- [ ] Update mapping logic in `scripts/resolve_test_targets.py` and its tests in `tests/test_resolve_test_targets.py`.
- [ ] Update test call sites in `scripts/tests/test_apidog_share_fetch.sh`, `scripts/tests/test_hook_wiring.sh`, etc.
- [ ] Run `ruff check scripts/` and `mypy --config-file mypy.ini scripts/`.
- [ ] Run `bash scripts/run-tests.sh --fast`.
- [ ] Run `bash scripts/harness-verify.sh`.
- [ ] Commit: `refactor: standardize internal python scripts to pep 8 snake_case`.

---

### Task 2: Root Directory Decluttering & Template Disambiguation
**Files:**
- Move: `hooks/` -> `templates/hooks/`
- Modify: `scripts/init-repo.sh`
- Modify: `scripts/tests/test_init_repo.sh`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/harness-adoption.md`

**Steps:**
- [ ] Create `templates/` and move `hooks/` to `templates/hooks/`.
- [ ] In `scripts/init-repo.sh`, update `HOOKS_SRC` to resolve `$SCRIPT_DIR/../templates/hooks` with backward-compatible fallback to `$SCRIPT_DIR/../hooks`.
- [ ] Update `scripts/tests/test_init_repo.sh` to verify template copying from the new location.
- [ ] Update documentation references in `README.md`, `docs/architecture.md`, and `docs/harness-adoption.md`.
- [ ] Run `bash scripts/tests/test_init_repo.sh`.
- [ ] Run `bash scripts/run-tests.sh --fast`.
- [ ] Run `bash scripts/harness-verify.sh`.
- [ ] Commit: `refactor: move external hook templates to templates/hooks/`.

---

### Task 3: Kiro Prompt Templates Re-Architecture
**Files:**
- Move: `prompts/` -> `config/kiro-prompts/` (or `config/kiro/prompts/`)
- Modify: `scripts/_lib.sh` (`install_kiro_prompts` and `uninstall_kiro_prompts`)
- Modify: `scripts/tests/test_install_agents_md.sh` (or any tests asserting prompt installation)
- Modify: `README.md`
- Modify: `docs/migration.md`

**Steps:**
- [ ] Move `prompts/*.md` to `config/kiro-prompts/*.md`.
- [ ] Update `install_kiro_prompts()` and `uninstall_kiro_prompts()` in `scripts/_lib.sh` to read from `$repo_dir/config/kiro-prompts/` with fallback to `$repo_dir/prompts/`.
- [ ] Update doc references in `README.md` and `docs/migration.md`.
- [ ] Run `bash scripts/tests/test_hook_wiring.sh` and related installer tests.
- [ ] Run `bash scripts/run-tests.sh --fast`.
- [ ] Run `bash scripts/harness-verify.sh`.
- [ ] Commit: `refactor: relocate kiro prompt templates under config/kiro-prompts/`.

---

### Task 4: Verification, Benchmarks, and Clean State Handoff
**Files:**
- Modify: `benchmarks/harness-suite.json` (if any benchmarked command paths shifted)
- Modify: `feature_list.json`
- Modify: `PROGRESS.md`

**Steps:**
- [ ] Run full benchmark suite: `bash scripts/harness-benchmark.sh -o /tmp/post-refactor-bench.json`.
- [ ] Compare against baseline: `bash scripts/harness-benchmark.sh --compare benchmarks/baseline.json /tmp/post-refactor-bench.json`. Verify 0 regressions and 0 SLA breaches.
- [ ] Run all 11 harness gates: `bash scripts/harness-verify.sh`.
- [ ] Run dual-mode session cleanup: `bash scripts/session-clean.sh`.
- [ ] Verify clean git status and state layer: `bash .claude/hooks/state-layer-guard.sh` and `bash .claude/hooks/clean-state-guard.sh`.
- [ ] Commit state changes and clean handoff.
