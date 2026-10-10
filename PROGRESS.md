# Session Progress Log

## Current State

**Last Updated:** 2026-10-10
**Active Feature:** none
**Harness lectures:** 1–12 closed (`docs/harness-creator/lecture-0N/summary.md`).
- Lecture 10 (why end-to-end testing changes results) closed: e2e_runner ported (5/5 tests), review feedback promotion documented.
- Lecture 11 (making the agent's runtime observable) closed: runtime_logger ported (13/13 tests, clean ruff/mypy), sprint contract & evaluator rubric documented.
- Lecture 12 (why every session must leave a clean state) closed: cleanup_scanner and benchmark_runner ported (22/22 tests, clean ruff/mypy), Invariant 4 enforced via Gate 11.
- Historical progress log pruned: `feat-001` through `feat-040` archived in `docs/progress-archive.md`.

## Status

### What's Done

*(Earlier features feat-001 through feat-040 are archived in [docs/progress-archive.md](docs/progress-archive.md). Per-feature evidence also recorded in `feature_list.json`.)*

- [x] feat-041: ported the course's `repo-reader.ts` (lecture 3) and `feature-list-validator.ts` (lecture 8) to Python under `docs/harness-creator/lecture-03/code/` and `lecture-08/code/`, validator adapted to this repo's schema. `state-layer-guard.sh` now blocks a `done` feature with empty `evidence` (only text counts: `[""]`, `true`, `5` are rejected) and no longer accepts lowercase `progress.md` (27/27). `run-tests.sh` now collects `docs/harness-creator/lecture-*/code/test_*.py`. Restored a JSON-message assertion that feat-040 dropped; renamed `lecture-07/raw/cmp-*-report.md` to `cmp-*-s1.md`.
- [x] Lecture 09 training (preventing premature declaration of victory): codified Three-Layer Termination Gate Hierarchy in `AGENTS.md`; fixed path bug in `.agents/hooks.json`; implemented and hardened `victory_detector.py` and `test_victory_detector.py` under `docs/harness-creator/lecture-09/code/` (6/6 tests passing, clean ruff); adversarial subagent audit verified Worker/Checker separation; authored `docs/harness-creator/lecture-09/summary.md` and `progress-detail.md`.
- [x] Lecture 10 training (why end-to-end testing changes results): ported `e2e_runner.py` and `test_e2e_runner.py` under `docs/harness-creator/lecture-10/code/` (5/5 tests passing, clean ruff/mypy); demonstrated that mock unit tests suffer a 75% false confidence rate on component boundaries; formulated 3-part agent-oriented error diagnostics (WHAT + WHY + FIX); audited repository review feedback promotion history; independent adversarial subagent audit verified deliverables; authored `docs/harness-creator/lecture-10/summary.md` and `progress-detail.md`.
- [x] feat-042: scoped Stop gate tests to changed files and installed repo git hooks. Added `scripts/get-changed-files.sh` (detects staged/unstaged/untracked files; 6/6 tests), `scripts/resolve_test_targets.py` (maps changed paths to targeted test files, falls back to ALL on shared infra; 7/7 tests), `scripts/run-tests.sh` `--changed` flag (3/3 tests), and wired `.claude/hooks/tests-guard.sh` to run `--changed` unless in harness-verify/full mode. Created `scripts/setup-git-hooks.sh` installing `pre-commit` (bash compat + state layer) and `pre-push` (harness verify) hooks (2/2 tests), wired into `init.sh`. All 72 tests pass, all 10 harness gates pass.
- [x] feat-043: fixed `_lib.sh` pip step under Homebrew Python (PEP 668). Replaced `--break-system-packages` with `install_python_sdk` creating/using an isolated runtime venv (`~/.agent-skills-setup/venv`). Updated `polish.py` and `polish_engine.py` to discover and load runtime venv `site-packages`. Added `test_hook_wiring.sh` assertions for absence of `--break-system-packages` and successful venv creation/pip logging.
- [x] Option 2 — Outside-agent cross-model verification (`claude` & `agy`): hardened `scripts/outside_agent.py` to include `--dangerously-skip-permissions` for `agy` non-interactive mode so headless tool requests are not auto-denied by jetski. Verified live bidirectional reviews: `from gemini` invoking `claude` returned code 0 with PASS, and `from claude` invoking `agy` returned code 0 with PASS. Added hermetic python venv stub to `scripts/tests/test_install_source_guard.sh` eliminating ambient PyPI network stalls.
- [x] Option 4 — Lecture 4 Exercise 3 follow-up (position bias scaled to ~10k tokens): built automated runner `docs/harness-creator/lecture-04/code/run_position_scaling_experiment.py` and executed 15 headless trials on Haiku 4.5 in ~11.8k-token monolithic context without explicit "read in full" instruction. Compliance collapsed from 100% down to 60% (Top 40%, Middle 60%, Bottom 80%), demonstrating that monolithic instruction bloat dilutes non-primary rule attention and confirming that deterministic harness guards are indispensable. Documented in `docs/harness-creator/lecture-04/position-experiment-scaling-10k.md` and `position-scaling-results.json`.
- [x] Lecture 11 training (making the agent's runtime observable): ported and extended runtime logger and observability diagnostic module under `docs/harness-creator/lecture-11/code/` (`runtime_logger.py`, `test_runtime_logger.py`, 13/13 tests passing, clean ruff/mypy); demonstrated that structured JSON logs with trace correlation turn failure debugging from guesswork into deterministic lookups; analyzed system vs process observability gaps in current repo; authored sprint contract and evaluator rubric; independent adversarial subagent audit verified deliverables and resolved documentation/table alignment findings; authored `docs/harness-creator/lecture-11/summary.md` and `progress-detail.md`.
- [x] feat-044: per-gate execution timing and structured JSON trace reporting in `harness-verify.sh`. Added portable millisecond duration measurement (`now_ms`) to each gate (displayed in console as `OK  gate (duration)`); added `--report <path>` and `--json` flags to emit structured trace reports with timestamp, total_duration_ms, and per-gate records; added `HARNESS_VERIFY_SLOW_MS` slow gate detection. `test_harness_verify.sh` passes 20/20 tests.
- [x] feat-045: scope exclusions in `feature_list.json` with automated `state-layer-guard` enforcement. Added optional `exclusions` list of string patterns to `feature_list.json` schema; updated `.claude/hooks/state-layer-guard.sh` to validate changed files against active feature exclusions (supporting exact paths and wildcard globs), blocking turn/commit with exit 2 and 3-part agent diagnostic (WHAT + WHY + FIX) on violation. `test_state_layer_guard.sh` passes 34/34 tests.
- [x] feat-046: multidimensional evaluator rubric in `outside_agent.py` review prompts. Added `--rubric` CLI flag and `EVALUATOR_RUBRIC` defining 4 core dimensions (Rule Conformance, Surgical Precision, Test Verifiability, Evidence Grounding scored 1-5) and required structured output format (Dimension Scores, Identified Risks, Concrete Failure Scenarios, Final Verdict). Enforces review-only usage (exits 2 on non-review). Unit tests in `test_outside_agent.py` verify rubric formatting, agent prompt augmentation, and CLI validation (91 passed).
- [x] Lecture 12 training (why every session must leave a clean state): ported and hardened `cleanup_scanner.py` and `benchmark_runner.py` under `docs/harness-creator/lecture-12/code/` (22/22 tests passing, clean ruff/mypy); audited 5 Invariants of clean state against target repo and identified Invariant 4 (stale artifacts/WIP files) as an open gap in current verification gates; added benchmark comparison and regression delta calculator; independent adversarial subagent audit passed; authored `docs/harness-creator/lecture-12/summary.md` and `progress-detail.md`.
- [x] feat-047: clean-state lifecycle, Invariant 4 gating, and repo pruning. Added `.claude/hooks/clean-state-guard.sh` (Gate 11 in `harness-verify.sh` & `pre-commit` git hook; 11/11 tests pass), implemented `scripts/session-clean.sh` for idempotent cache purge and 5-invariant validation (6/6 tests pass), and pruned historical `PROGRESS.md` into `docs/progress-archive.md`.
- [x] feat-048: live harness self-benchmark runner and baseline suite. Created `benchmarks/harness-suite.json` (7 tasks with SLA latency targets), implemented `scripts/harness_benchmark.py` and `scripts/harness-benchmark.sh` supporting multi-iteration timing, SLA checking, and `--compare` delta regression tracking (+15% threshold; 10/10 tests pass), added `--dry-run` to `session-clean.sh` (7/7 tests pass), and generated canonical `benchmarks/baseline.json` with 100% SLA compliance (7/7 tasks PASS in 8129ms).
- [x] feat-049: Python module naming standardization to PEP 8 snake_case. Standardized 5 internal Python scripts from kebab-case to snake_case (`credential_backend_check.py`, `hook_wiring_check.py`, `skill_frontmatter_check.py`, `skill_path_var_check.py`, `apidog_share_fetch.py`). Updated callers in `.claude/hooks/credential-backend-guard.sh`, `hook-wiring-guard.sh`, `skill-paths-guard.sh`, `harness-verify.sh`, `resolve_test_targets.py`, and documentation in `skills/apidog/`. Verified 100% clean imports across all 5 modules, `tests/test_resolve_test_targets.py` passed (9/9), `run-tests.sh --fast` passed (78/78), and all 11 gates in `harness-verify.sh` passed.
- [x] feat-050: Template library relocation from hooks/ to templates/hooks/. Relocated root hooks/ to templates/hooks/ via git mv. Updated hook resolution path in scripts/init-repo.sh, scripts/tests/test_init_repo.sh, scripts/tests/test_shared_hook_templates.sh, and added templates to REPO_SUBDIRS in scripts/skill_path_var_check.py. Updated references across README.md, docs/architecture.md, and AGENTS.md. Verified with test_init_repo.sh (16/16), test_shared_hook_templates.sh (20/20), run-tests.sh --fast (78/78), and all 11 gates in harness-verify.sh.

### What's In Progress

- Nothing active (WIP=0, clean state).

### What's Next

**Prioritized Technical Queue (WIP=1):**
1. **Smoke test verification:** Re-run live `codex-kiro` and `agy` smoke tests against feat-033 fixes; trust repo hooks in Codex on each host.
   - *Verification:* `outside-agent.sh run --purpose review` exits 0.
2. **Fresh-session cross-repo tests:** Run fresh-session test on real `hangar` and `atelier` `main` once logged in headless.

**Pending Owner Decisions (Blocked on Human):**
- **daily-ai-video-pipeline:** Decide whether to create private remote GitHub repo or remain local.
- **Hermes cleanup:** Decide whether to drop residual `~/.hermes` configs from `skills/infra/kiro-gateway` or keep for other hosts.
- **Handy branch:** Decide if `local/zh-tw-default` needs further integration or remains fork-only.

## Blockers / Risks

- **`_lib.sh` pip step on Homebrew Python (PEP 668) [RESOLVED in feat-043]:** Replaced `--break-system-packages` with isolated runtime venv (`~/.agent-skills-setup/venv`) and automatic `site-packages` discovery.

- **`agy` latency varies by caller and environment (2026-10-08, cause unconfirmed):** a trivial
  `agy --dangerously-skip-permissions -p` prompt took 221s from the Claude Code session, above
  `outside-agent.sh`'s 110s default `--timeout`. The earlier `agy failed with an unclassified error`
  during a review is likely the same slowness, but it was not reproduced through the wrapper. Not a
  code defect. For a review that may fall through to `agy`, pass `--timeout 900`.

## Decisions Made

- **Case-sensitive filesystem assumed repo-wide (owner, 2026-10-07):** All host environments, Docker
  containers, and CI operate on case-sensitive filesystems. New hooks and guards must not add
  case-insensitive fallback logic (e.g. checking both lowercase and uppercase variations).
  The legacy `progress.md` fallback in `state-layer-guard.sh` is removed.
- **Retain `feature_list.json` without symlinks (owner, 2026-10-07):** Keep the canonical name
  `feature_list.json` to preserve compatibility with external harness scanners (`validate-harness.mjs`
  in the harness-creator skill; `repo-reader.ts` and `feature-list-validator.ts` in the
  learn-harness-engineering course repo). Both course tools are ported to Python under
  `docs/harness-creator/lecture-03/code/` and `lecture-08/code/`; the validator is adapted to this
  repo's schema, since the original expects a bare array with `passes`/`verification`. No alias
  symlinks (`feature-list.json`).
- **Lecture-07 layout stays as is (2026-10-08):** `task-atomization-plan.md` remains in `code/` and
  `hidden_accept.py` in `raw/`. Lecture-06 keeps its grader in `raw/` and lecture-04 has no `raw/`,
  so there is no L4/L6 layout to match. Only the `cmp-*-report.md` to `cmp-*-s1.md` rename followed lecture-06.
- **Auto-merge in hangar and atelier stays** (owner, 2026-10-01): Renovate automerge and
  the macmini agents' direct pushes continue until scale-up or a significant incident.
  The rule is now recorded in both repos' `PROGRESS.md` and `AGENTS.md`, so a session
  there can read it without this repo's memory.

- **Did not add a fake "one feature at a time" placeholder feature list**:
  this repo is an ongoing multi-skill toolkit, not a single-feature build, so a
  literal `feature_list.json` reflects real completed/queued work instead of a
  templated placeholder. See `AGENTS.md` for this repo's actual working rules.
- **`init.sh` delegates rather than reimplements**: `scripts/harness-verify.sh`
  is already this repo's single source of truth for verification gates (same
  checks the Stop hooks run). A second implementation in `init.sh` would drift
  from it the first time either changed.
- **Removed a broken `ask` permission rule rather than patching it wider**:
  `codex-kiro` (a genuinely different model) found `Bash(bash scripts/install.sh*)`
  trivially bypassed by any other invocation form. Enumerating every bypass is
  not a stable boundary, so `AGENTS.md` now documents that boundary as
  advisory-only instead of pretending an unenforceable rule enforces it.
- **Only 2 of ~400 bare `python3`/`mypy`/`pytest` call sites were pointed at
  the new `.venv`**: everything else either ships to other people's machines
  (installer scripts, credential helpers, hook templates copied into other
  repos) and must keep resolving from ambient PATH, or only imports stdlib
  and needs no third-party package at all. Confirmed via a full call-site
  audit before touching anything, not assumed.
- **Brought in a third model (`agy`) specifically because `codex-kiro` had
  just failed once**: a single review tool's reliability wobble is a real
  reason to add a second source, not just retry the same one. That review
  paid off with a genuine finding (version-drift gap) — but also produced
  two confident, false claims from `agy` itself, reinforcing that a third
  model is one more source to verify, not one more source to trust by
  default.
- **`google-generativeai` deprecation confirmed but not migrated** (migrated later in feat-019): real,
  checked against PyPI directly, not just claimed by either review model —
  but migrating it means touching `polish_engine.py`'s actual Gemini
  integration code, a different-shaped change than this session's
  dev-tooling scope. Flagged in Blockers/Risks rather than silently
  expanded into or silently dropped.
- **Redesigned the exclusion test rather than accepting the first null
  result**: attempt 1 (mirror a sibling file) was fully answerable from the
  sibling alone, so stripping Instructions/State/Feedback never got
  exercised — a null result about the task, not about the subsystems.
  Attempt 2 deliberately chose a task with real ambiguity, a non-obvious
  stopping point, and a mechanically verifiable outcome (a new gate across
  4 integration points) instead of a bigger or different-repo task — size
  wasn't the problem, shortcut-ability was.
- **Caught and excluded a confound rather than reporting all 4 conditions
  as comparable**: the no-feedback variant's ablation (delete
  `scripts/tests/` to remove Feedback) happened to also delete the file
  containing the pre-existing bug the other 3 conditions found. Its silence
  on that bug is an artifact of the ablation, not a finding, and it was
  explicitly excluded from that comparison rather than silently averaged in.
- **Recorded the exclusion-test result as a correlation, not a proven
  cause**: `AGENTS.md`'s presence correlates with fixing (not just
  flagging) an incidentally-found bug, cross-validated across 3 independent
  sandboxes finding the identical bug — but `AGENTS.md` has no instruction
  resembling "fix bugs you find along the way" (checked directly, no
  match), so the causal mechanism is explicitly left unconfirmed rather
  than overclaimed.

Full training-exercise narrative (diagnostic-loop scores, the verification-gap
measurement, the same-model-review lesson): `docs/harness-creator/lecture-01/`
and `docs/harness-creator/lecture-02/`.

## Archived history

`Files Modified This Session` and `Evidence of Completion` moved to
[docs/progress-archive.md](docs/progress-archive.md). The first stops at feat-014; the second
has no entries for feat-011 to feat-022. Per-feature evidence lives in `feature_list.json`.

## Notes for Next Session

Read `AGENTS.md` first — it documents real incidents (bash 3.2 target, symlinked
skills, hook exit codes) that are not obvious from the code alone. Then run
`./init.sh` to see current gate status before making changes.
