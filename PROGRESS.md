# Session Progress Log

## Current State

**Last Updated:** 2026-10-10
**Active Feature:** none
**Harness lectures:** 1–13 closed (`docs/harness-creator/lecture-0N/summary.md`).
- Lecture 10 (why end-to-end testing changes results) closed: e2e_runner ported (5/5 tests), review feedback promotion documented.
- Lecture 11 (making the agent's runtime observable) closed: runtime_logger ported (13/13 tests, clean ruff/mypy), sprint contract & evaluator rubric documented.
- Lecture 12 (why every session must leave a clean state) closed: cleanup_scanner and benchmark_runner ported (22/22 tests, clean ruff/mypy), Invariant 4 enforced via Gate 11.
- Lecture 13 (from manual prompting to autonomous loops) closed: ratchet_loop ported (9/9 tests, clean ruff/mypy), goal and loop state templates documented.
- Historical progress log pruned: `feat-001` through `feat-050` archived in `docs/progress-archive.md`.

## Status

### What's Done

*(Earlier features feat-001 through feat-050 are archived in [docs/progress-archive.md](docs/progress-archive.md). Per-feature evidence also recorded in `feature_list.json` and `docs/archive/features/`.)*

- [x] feat-051: Relocate Kiro workflow prompts from prompts/ to agents/kiro/prompts/. Relocated root prompts/ to agents/kiro/prompts/ via git mv. Atomically updated install_kiro_prompts and uninstall_kiro_prompts in scripts/_lib.sh to source from agents/kiro/prompts/. Added automated test suite scripts/tests/test_kiro_prompts.sh verifying isolated mock home installations, path substitutions, and uninstalls against both mock repo and live repo (5/5 checks passed). Updated docs/architecture.md. Verified with run-tests.sh --fast (79/79 passed) and all 11 gates in harness-verify.sh.
- [x] feat-052: State layer feature archival to docs/archive/features/. Partitioned 40 historical completed features (feat-001 through feat-040) into docs/archive/features/archive-feat-001-040.json, reducing feature_list.json from 513 lines to 218 lines. Extended .claude/hooks/state-layer-guard.sh to validate archive_references, checking file existence, JSON validity, features schema, and unevidenced completion across both active and archived features with 3-part diagnostics. Added 4 new test cases to .claude/hooks/tests/test_state_layer_guard.sh (40/40 passed under both bash 5 and macOS /bin/bash 3.2). Verified run-tests.sh --fast (79/79 passed) and all 11 gates in harness-verify.sh.
- [x] feat-053: Elevate active repo guard rails to universal harness/guards/. Elevated all 16 guard rails and 12 guard test suites from .claude/hooks/ to agent-agnostic harness/guards/ with backward-compatible relative symlink .claude/hooks -> ../harness/guards. Updated harness-verify.sh, setup-git-hooks.sh, .agents/hooks.json, .codex/hooks.json, run-tests.sh, resolve_test_targets.py, and documentation in docs/architecture.md. Added harness/ to REPO_SUBDIRS in skill_path_var_check.py. Verified run-tests.sh --fast (79/79 passed) and all 11 gates in harness-verify.sh.
- [x] feat-054: Automated evaluation trace loop and trend reporter. Implemented `scripts/trace_evaluation.py` and `scripts/trace-evaluation.sh` supporting snapshot recording to `docs/telemetry/evaluation-trace.jsonl`, formatted `--trend` historical analysis, `--check-thresholds` for state layer token bloat detection (`feature_list.json` > 250 lines, `PROGRESS.md` > 150 lines), and `--json` export. Created automated test suite `scripts/tests/test_trace_evaluation.sh` (9/9 passed). Fast test suite runs 80/80 passed with zero failures.
- [x] feat-055: Wire evaluation trace telemetry into `session-clean.sh` and `AGENTS.md` base workflow. Integrated `scripts/trace-evaluation.sh` snapshot recording and `--trend` display into `scripts/session-clean.sh`, added state layer threshold checks during handoffs, extended `scripts/tests/test_session_clean.sh` (8/8 passed), and documented commands in `AGENTS.md` Quick Reference and End-of-Session workflow.
- [x] feat-056: Auto duration delta calculation, process tree agent detection, and Markdown trace dashboard. Upgraded `scripts/trace_evaluation.py` to auto-calculate elapsed duration since previous trace entries when `--duration-ms` is omitted, inspect process tree ancestry in `detect_agent()` via `get_process_ancestors()` (eliminating ambiguous directory checks), format times human-readably (ms, s, m, h), and auto-generate `docs/telemetry/SUMMARY.md` Markdown dashboard table on record. Added tests in `scripts/tests/test_trace_evaluation.sh` (12/12 passed).
- [x] feat-057: Subagent telemetry tracking (self subagents and outside agents) and independent review verification. Added execution logging (`_log_outside_run`) to `scripts/outside_agent.py` recording runs to both state and local telemetry (`docs/telemetry/outside-agent-runs.jsonl`, gitignored). Implemented subagent tracking in `scripts/trace_evaluation.py` (`--self-subagents`, `--outside-subagents`, auto-detection via `auto_detect_outside_runs`, defensive parsing against malformed lines and naive/aware datetimes, cross-platform Python 3.9+ compatibility). Updated `SUMMARY.md` and CLI trend table with Subagents column. Added unit tests in `scripts/tests/test_trace_evaluation.sh` (16/16 passed across all timezones) and `tests/test_outside_agent.py` (92 passed, 1 skipped). Adversarially reviewed across 5 iterative rounds with both self subagents and outside independent agents (Claude Code `outside-agent.sh`) achieving CLEAN PASS.

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
