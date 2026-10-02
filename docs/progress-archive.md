# PROGRESS archive

Frozen history moved out of `PROGRESS.md` on 2026-10-04 (Lecture 5). Nothing here is
current state: "Files Modified" stops at feat-014, and "Evidence of Completion" has no entries for
feat-011 to feat-022; its early numbers (8 gates, 53 tests) are from when they were written. Current evidence lives in `feature_list.json`.

## Files Modified This Session

- `registry.txt`, `scripts/_lib.sh`, `scripts/validate-registry.sh`,
  `scripts/tests/test_registry_types.sh`, `README.md`, `.claude/settings.json`
  — feat-001 and feat-002 (see commit 5b023f3)
- `init.sh`, `feature_list.json`, `PROGRESS.md` — added as this repo's state
  layer (previously missing; a fresh session had no way to see what was done,
  in progress, or next without asking someone who remembered)
- `scripts/_settings_merge.py` — feat-003, one-line type annotation fix
- `README.md` (line 388), `scripts/tests/test_registry_types.sh` (Test 23
  rewritten, Test 24 added) — feat-004, merged from isolated-worktree
  subagent output after independent review
- `docs/harness-creator/lecture-01/summary.md`,
  `docs/harness-creator/lecture-01/progress-detail.md` — the full Lecture 1
  training writeup, split out of this file to keep it durable state rather
  than a training log
- `scripts/install.sh`, `scripts/uninstall.sh`, `scripts/_lib.sh`,
  `scripts/update.sh`, `scripts/tests/test_hook_wiring.sh`, `README.md`,
  `docs/migration.md`, `skills/utils/SKILL.md`,
  `skills/utils/polish-input/README.md`, `.python-version` (new) — feat-005
- `.claude/settings.json`, `AGENTS.md` — feat-006 (permissions block, fixed
  after `codex-kiro` review)
- `docs/harness-creator/lecture-02/summary.md`,
  `docs/harness-creator/lecture-02/progress-detail.md` — the full Lecture 2
  training writeup
- `.gitignore`, `requirements-dev.txt` (new), `.claude/hooks/types-guard.sh`,
  `scripts/run-tests.sh`, `.claude/hooks/tests/test_types_guard.sh`,
  `mypy.ini`, `AGENTS.md` — feat-007 (`.venv/` itself is gitignored, not
  committed)
- `.claude/hooks/types-guard.sh`, `scripts/run-tests.sh` (further edited),
  `docs/harness-creator/lecture-02/summary.md`,
  `docs/harness-creator/lecture-02/progress-detail.md` — feat-008
  (version-drift guard + multi-model review record)
- `docs/harness-creator/lecture-02/summary.md`,
  `docs/harness-creator/lecture-02/progress-detail.md`, `feature_list.json`,
  this `PROGRESS.md` — feat-009 (exclusion-test attempt 2, non-null result,
  confound recorded, correlation-vs-causation distinction made explicit).
  No repo functionality changed by feat-009 itself — the shellcheck gates
  built during the test lived only in the disposable `/tmp/exclusion-test-v2/`
  variant directories, not in this repo.
- `docs/harness-creator/lecture-02/summary.md`,
  `docs/harness-creator/lecture-02/progress-detail.md`, `feature_list.json`,
  this `PROGRESS.md` — feat-010 (affordance analysis, Lecture 2 closed out).
  No repo functionality changed — classification exercise only.
- `docs/architecture.md`, `pyproject.toml`, `docs/harness-creator/lecture-03/`,
  `PROGRESS.md` (renamed from `progress.md`), `.claude/hooks/state-layer-guard.sh`,
  `.claude/hooks/tests/test_state_layer_guard.sh`, `AGENTS.md`, `feature_list.json`
  — feat-014 (Lecture 3: Repository as System of Record, discoverability Grade A
  100/100, direct canonical uppercase upgrade, dual-agent empirical Fresh Session
  test via Claude Code and blind subagent).

## Evidence of Completion

- [x] Tests pass: `bash scripts/run-tests.sh --fast` → 53 passed, 0 failed
- [x] Type check clean: `python3 -m mypy --config-file mypy.ini .` → Success:
      no issues found in 27 source files
- [x] `./init.sh` → all 8 gates pass (registry, types, tests, skill paths,
      cred backends, hook wiring, state layer, secret scan)
- [x] Registry validates: `bash scripts/validate-registry.sh` → clean
- [x] Independently verified by a second agent (`kiro-cli`, no shared context):
      given only `AGENTS.md` + `feature_list.json` + `PROGRESS.md`, correctly
      reconstructed feature status, the exact blocking file/line, and next
      steps
- [x] feat-004's test fix independently confirmed by a genuinely different
      model (`codex-kiro`) and by mutation testing — see
      `docs/harness-creator/lecture-01/progress-detail.md` for the full log
- [x] feat-005: `bash scripts/tests/test_hook_wiring.sh` → 18/18 passed;
      no `--with-hook`/`HOOK_SKILLS` references remain outside archived docs
      (`grep -rn` confirmed)
- [x] feat-006: `jq -e '.permissions' .claude/settings.json` → valid,
      deny-only after the fix; local glob-fixture test confirmed the
      `*` → `**` fix actually crosses path segments (not just claimed) — see
      `docs/harness-creator/lecture-02/progress-detail.md`
- [x] feat-007: `osv-scanner scan source --recursive .` → No issues found
      (verbose form confirmed `requirements-dev.txt` was actually scanned —
      51 packages — not the "no package sources found" bypass);
      `bash .claude/hooks/tests/test_types_guard.sh` → 9/9 passed;
      `.venv/bin/mypy` and bare `mypy` give identical clean results;
      `bash .claude/hooks/secret-scan.sh` run manually end-to-end (zero prior
      test coverage on this exact path) → exit 0
- [x] feat-008: simulated version drift (`echo 9.9.9 > .python-version`) →
      both `types-guard.sh` (exit 2) and `run-tests.sh` (exit 1) correctly
      blocked with rebuild instructions instead of silently falling back;
      restored the pin, reran clean; `bash scripts/run-tests.sh --fast` →
      53 passed, 0 failed after the fix; `pip show httpx2` +
      `pipdeptree --reverse -p httpx2` refuted `agy`'s typosquat claim;
      `WebFetch` on `pypi.org/project/google-generativeai/` confirmed the
      deprecation claim
- [x] feat-009: 4 fresh (non-fork) subagents dispatched to isolated
      `/tmp/exclusion-test-v2/` copies (git-archive'd tracked files only,
      not the 380MB `.venv`); all 4 completed the shellcheck-gate task, but
      only the `AGENTS.md`-present condition fixed rather than flagged a
      pre-existing bug all 3 valid conditions found independently; read
      `.claude/settings.json` directly in each variant to confirm wiring;
      checked all 4 guard scripts for bash-4+-only syntax against the
      documented bash-3.2 floor (none found, including in the 3 conditions
      without `AGENTS.md`); caught the no-feedback confound via direct file
      existence check rather than trusting the "not applicable" cell
- [x] feat-010: both cases drawn from real events already in this session's
      own record (the polish-input hook malfunctions, the feat-009 exit-128
      failures) — not invented; each classified into exactly one gulf with
      the specific mechanism named, not just labeled
- [x] feat-023: `pytest skills/utils/polish-input/tests/test_polish.py` → 29 passed
      (4 new AGY PreInvocation tests); `bash scripts/tests/test_hook_wiring.sh` →
      37 checks passed (7 new Gemini hook wiring assertions); `python3 docs/harness-creator/lecture-04/code/split_simulation.py` →
      clean; `bash scripts/run-tests.sh --fast` → 56 passed, 0 failed; `./init.sh` →
      all 9 gates passed clean.
- [x] feat-024: `bash .claude/hooks/tests/test_precommit_sh_check.sh` → 14 passed;
      `bash .claude/hooks/tests/test_sh_check.sh` → 16 passed;
      `bash .claude/hooks/tests/test_py_check.sh` → 18 passed;
      `bash .claude/hooks/tests/test_stop_verify.sh` → 6 passed;
      `bash scripts/run-tests.sh --fast` → 57 passed, 0 failed; `./init.sh` →
      all 9 gates passed clean. Live AGY execution confirmed PreToolUse, PostToolUse, and Stop hook triggering.
- [x] feat-025: commit `112acf5` on `main`;
      `pytest skills/utils/polish-input/tests/test_polish.py` → 32 passed (including tail seek and payload variations);
      `bash scripts/run-tests.sh --fast` → 57 passed, 0 failed; `./init.sh` → all 9 gates passed clean;
      statusline execution reduced from ~250ms to ~21ms with zero recurring errors.

- [x] feat-026: `bash scripts/tests/test_statusline_command.sh` → 8 passed (fails on the old script: 3.1s with stdin open); `bash scripts/tests/test_install_agents_md.sh` → 17 passed; live AGY session in tmux renders `herohsu@VOMAC4294:/tmp` with zero `signal: killed` in the new log; after `install-agents-md.sh`, `[polish]` appears only in `~/.gemini/GEMINI.md`.
- [x] feat-027: commit `0943b0f`; `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh` → 40 passed (4 new codex tests failed on the old code first); live `zsh -i -c 'codex-kiro exec ...'` → provider kiro, answered, and confirmed the `~/.codex` rules load (Fail Loud rule present); `./init.sh` → all gates passed.
- [x] feat-028: `pytest skills/utils/polish-input/tests` → 59 passed (9 new cases failed first, built from today's real bad outputs); live hook through the gateway: "yes" → silent, "use codex-kiro only not codex directly" → "Use codex-kiro only, not codex directly.", the meaning-flip prompt keeps its meaning; `./init.sh` → all gates passed.
- [x] feat-029: `scripts/tests/test_setup_tmux_conf.sh` → 10 OK under bash 5 and `/bin/bash` 3.2 (failed first, script missing); moving the line out of the Darwin branch fails `linux: update-environment not set`; on macmini, with `SSH_CONNECTION` cleared from the session, `agy -p` authenticated via keyring; `./init.sh` → all gates passed.
