# Session Progress Log

## Current State

**Last Updated:** 2026-10-02
**Active Feature:** none. feat-020 (L1–L4 harness for hangar and atelier) is merged and pushed in both repos; `./init.sh` passes all 9 gates.
**Active Feature:** none. feat-026 closed out; `./init.sh` passes all 9 gates.
**Active Feature:** none. feat-027 closed out; `./init.sh` passes all 9 gates.
**Active Feature:** none. feat-028 closed out; `./init.sh` passes all 9 gates.
**Active Feature:** none. feat-029 closed out; `./init.sh` passes all 9 gates.
**Lecture 4 is closed.** Exercises 1 (SNR audit) and 3 (position test) were run. Two parts were not:
exercise 1's relocation step was skipped on purpose, since the noise is in the global rules file
(summary §3.4), and exercise 2's before/after success-rate comparison has no baseline, because
`AGENTS.md` was already under 100 lines before this lecture. feat-015's first pass overclaimed,
and feat-016 corrected it: it added `bash-compat-guard.sh` (Shell Portability had no
repo-wide check), fixed `split_simulation.py` (real savings 26.6%, not 67.7%), added
Source/Applies/Expires metadata and Load-when conditions to `AGENTS.md` (96 lines), and ran
exercise 3: 15/15 compliance at top/middle/bottom, a null result at this size. Corrections
table: `docs/harness-creator/lecture-04/summary.md` §4.

## Status

### What's Done

- [x] feat-001: pinned external skill sources (`github`/`github-skill` registry
  entries) to a commit SHA via optional `@ref` syntax, so `install.sh`/`update.sh`
  no longer silently track the mutable upstream default branch
- [x] feat-002: repo-level `.claude/settings.json` now sets `attribution.commit`
  and `attribution.pr` to `""`, so commits/PRs made in this repo never carry a
  Co-Authored-By or Generated-with trailer
- [x] feat-003: annotated `changed` in `scripts/_settings_merge.py:85`, closing
  the pre-existing mypy gap — `./init.sh` now passes all 7 gates clean
- [x] feat-004: ran a verification-gap exercise (5 dispatched cleanup tasks,
  claimed-done vs. independently re-verified); merged the 2 real fixes it
  produced (README `@ref` consistency; a corrected uninstall `@ref` test that
  a second-opinion review caught passing regardless of whether the feature it
  tested actually worked)
- [x] feat-005: made `polish-input` default-install (removed `--with-hook`/
  `HOOK_SKILLS` entirely — its only consumer); pinned `.python-version` to
  `3.14.7` as the start of Lecture 2's Environment-subsystem work, which
  surfaced that `mypy` was only clean thanks to ambient packages on the old
  interpreter — installed the real set (mypy/ruff/pytest/lxml/
  google-generativeai) under 3.14.7 to restore a genuinely green suite
- [x] feat-007: built a real isolated `.venv` (not the shared ambient pyenv
  env) with only this repo's actual deps, generated `requirements-dev.txt`
  from it, and ran `osv-scanner` for real — clean, no CVEs (the earlier CVE
  list was an artifact of the polluted ambient environment, not this repo's
  real dependencies). Rewired only the two gates that need third-party
  packages (`types-guard.sh`, `run-tests.sh`) to prefer `.venv/bin/*` with a
  bare-interpreter fallback; resolved `codex-kiro`'s python-version-vs-
  mypy.ini finding as a documentation staleness issue, not a real conflict
- [x] feat-008: multi-model review of feat-007's fallback logic (`codex-kiro`
  failed once, succeeded on retry; `agy` — a third, different model family —
  brought in because of that reliability wobble) found a real gap: the
  fallback only checked executability, not that `.venv` matched
  `.python-version`. Fixed with a loud-fail version-drift check, confirmed
  by simulating drift. `agy` also produced two confident, false claims
  (Python 3.14.7 "doesn't exist"; `httpx2`/`httpcore2` are "typosquats") —
  checked and refuted, not accepted. One claim converged and checked out:
  `google-generativeai` is genuinely deprecated (confirmed via PyPI directly)
  — real finding, deliberately not actioned this session (touches shipped
  code, different scope)
- [x] Added `init.sh` as the canonical startup/verification entrypoint (delegates
  to `scripts/harness-verify.sh` — no duplicated logic)
- [x] Added `feature_list.json` and this `PROGRESS.md` as real state artifacts
- [x] feat-009: ran Lecture 2's controlled variable exclusion test a second
  time (attempt 1 — mirror a sibling file — came back null, task didn't
  discriminate). Attempt 2 used a harder task (add a shellcheck gate across
  4 real integration points) across baseline/no-instructions/no-state/
  no-feedback conditions — non-null: only the condition with `AGENTS.md`
  present fixed a pre-existing bug it found rather than just flagging it.
  Caught and excluded a confound in the no-feedback condition (its ablation
  deleted the exact file the bug lived in). Explicitly did not overclaim
  causation — `AGENTS.md` has no "fix incidental bugs" instruction, so this
  is a confirmed correlation, not a confirmed mechanism.
- [x] feat-010: ran Lecture 2's affordance-analysis exercise (Gulf of
  Execution / Gulf of Evaluation), classifying two real cases from this
  session instead of inventing synthetic ones — the `polish-input` hook's
  fabricated refusals/identities (Gulf of Evaluation: no feedback loop on
  the hook's own output) and the feat-009 sandboxes' spurious exit-128
  failures (Gulf of Execution: `harness-verify.sh` offers no way to run a
  subset of gates). Neither gap fixed — classification only, per the
  exercise's scope. **Lecture 2 is now fully closed.**
- [x] feat-011: audited all 15 skills and 46 sub-skills for Antigravity (agy)
  compatibility. Normalized frontmatter across all 31 Format A `IMPL.md` files
  by adding `name` and `description` fields, ensuring progressive disclosure
  works cleanly in agy while preserving Claude Code slash/subcommand metadata.
  Ran full harness verification: all 8 gates pass clean.
- [x] feat-012: `wire_hook`/`rewire_hooks` no longer map kiro to
  `~/.claude/settings.json` (it double-wired polish-input into Claude Code).
  `test_kiro_gateway.sh` not run — local Docker daemon hung, unrelated.
- [x] feat-013: `install.sh` refuses to run from a worktree or non-default
  branch (`--allow-non-main` overrides; CI uses it) and a bare re-run replays
  the saved agent selection. Agents may now run it without asking.
- [x] feat-014: Lecture 3 (harness-creator training) completed. Raised discoverability
  score on `repo-reader.ts` from 60/100 (Grade C) to 100/100 (Grade A) by authoring
  canonical `docs/architecture.md`, upgrading directly to canonical uppercase
  `PROGRESS.md` (with `state-layer-guard.sh` and tests supporting both canonical and
  legacy names), and adding standard PEP 621 `pyproject.toml` manifest — with zero
  root symlinks. Completed and documented all 3 Lecture 3 exercises (Fresh Session
  Test, Knowledge Visibility Gap audit of 20 constraints at 5.0%, and ACID
  assessment) in `docs/harness-creator/lecture-03/`.
- [x] feat-015: Lecture 4 (harness-creator training) completed. Elevated root
  `AGENTS.md` to an explicit router (82 lines) with a dedicated `## Topic Docs`
  routing section (`docs/architecture.md`, `agents/engineering-rules.md`,
  `skills/README.md`, `docs/harness-creator/`, `docs/migration.md`). Created
  standalone audit/simulation tool `docs/harness-creator/lecture-04/code/split_simulation.py`
  demonstrating 23.2% average SNR across 5 canonical tasks (76.8% noise under
  monolithic context), 67.7% context token savings via router+topic splitting,
  and mapped 'Lost in the Middle' position depth (30%-70% danger window), confirming
  middle invariants must be backed by deterministic guard hooks. Documented full
  analysis in `docs/harness-creator/lecture-04/`. *(Overclaimed; corrected by feat-016.)*
- [x] feat-016: Lecture 4 completion. New `bash-compat-guard.sh` (wired into
  `harness-verify.sh` + Stop/SubagentStop, 15-case test green under `/bin/bash` 3.2);
  `split_simulation.py` fixed; `AGENTS.md` rule metadata; exercise 3 run and recorded in
  `docs/harness-creator/lecture-04/position-experiment.md`.

- [x] feat-018: split the global rules. The production gate procedure (old Part IV) is now
  the required `spec-workflow` skill, and `engineering-rules.md` keeps host-neutral triggers
  only (147 → 86 lines). Guarded by `scripts/tests/test_engineering_rules_scope.sh`.
  Deployed to all four hosts via `scripts/install-agents-md.sh`.

- [x] feat-017: `harness-verify.sh` now reports a self-skipping gate as `SKIP` and names it
  in the summary. That exposed `secret scan` as a second silent skip (gitleaks and
  osv-scanner were missing); both are now installed and the real scans are clean.

- [x] feat-019: polish-input's Gemini backend moved to `google-genai` (API key only). The
  Antigravity OAuth path was removed: it already failed with a 403 scope error, and
  `google-genai` can't use OAuth for the Gemini API. Default model `gemini-1.5-flash`
  (retired) → `gemini-3.5-flash-lite`. Not live-tested: no Gemini key on this machine.

- [x] feat-020: refreshed the five shared hook templates from hangar and atelier (turn-scope
  gating, stderr and exit 2), added `scripts/tests/test_shared_hook_templates.sh` (17 cases) and `docs/harness-adoption.md`. Built a custom L1–L4 set for hangar
  and atelier in scratch clones on branch `harness/l1-l4`, then fixed what review of that work
  found (an independent subagent review plus mutation runs showed hangar's and the template's
  tests had blind spots, now closed): gitleaks `--source .` in all three `secret-scan` copies, and atelier's `py-guard` and
  `ts-guard` gating on the merge-base (they skipped committed and new files).
- [x] feat-021: registered `pip google-genai>=2.25.0` in `registry.txt` with validator coverage;
  bumped `obra/superpowers` pin to `8ca22dba` (15 skills installed);
  added `install_statusline` in `_lib.sh` and wired into `install.sh` so statusline is configured
  automatically for supported agents (`claude`, `gemini`) if absent; installed `google-genai` in
  `.venv` and pyenv global python; deployed rules to all hosts; applied agent CLI updates
  (`hermes` updated to `ef201323`, `claude`/`codex`/`agy` already current); verified `./init.sh`
  clean across all 9 gates.

- [x] feat-022: added native Codex CLI hook wiring support and corrected outdated documentation.
  Updated `scripts/_lib.sh` (`wire_hook`, `rewire_hooks`, `unwire_hook`) and `agent_skills_dir`
  to support Codex targeting `${CODEX_HOME:-$HOME/.codex}/hooks.json` via `_settings_merge.py`.
  Updated `skills/utils/polish-input/lib/polish.py`'s `detect_agent()` to recognize `/.codex/`.
  Updated `scripts/harness-verify.sh`, `scripts/install.sh`, `scripts/update.sh`, and `README.md`.
  Added unit tests in `skills/utils/polish-input/tests/test_polish.py` and integration tests in
  `scripts/tests/test_hook_wiring.sh` (wire, rewire, unwire, CODEX_HOME override). `./init.sh`
  passes all 9 gates clean.

- [x] feat-023: migrated AGY prompt polishing from system prompt rule in `GEMINI.md` to native `PreInvocation` lifecycle hook in `~/.gemini/config/hooks.json` (eliminating 8-15s response latency from reasoning models). Updated `polish.py` with transcript parser and `PreInvocation` protocol, `hook.json` with `PreInvocation`, `_settings_merge.py` to support AGY hooks format, and `_lib.sh` to wire `~/.gemini/config/hooks.json`. Removed prompt polish rule from `agents/engineering-rules.md` and `split_simulation.py`.
- [x] feat-024: multi-agent workspace hook support (AGY and Codex CLI) with cross-agent payload handling. Configured repository-level lifecycle hooks for AGY (`.agents/hooks.json`) and Codex CLI (`.codex/hooks.json`), mirroring Claude Code (`.claude/settings.json`). Updated `precommit-sh-check.sh` to support both Claude/Codex (`tool_input.command`) and AGY (`toolCall.args.CommandLine`) payloads, returning `{"decision": "allow"|"deny"}` for AGY and exit 0/2 for Claude/Codex. Updated `sh-check.sh` and `py-check.sh` to recognize AGY `TargetFile` and `AbsolutePath` arguments. Implemented `.claude/hooks/stop-verify.sh` as universal Stop hook wrapper running `harness-verify.sh` across all agent formats. Added unit and integration tests across all modified and new hooks (57 tests passing). Live verified under AGY engine.
- [x] feat-025: AGY statusline timeout resolution and polish-input streaming squeeze. Resolved recurring AGY statusLine timeout errors (killed signal) by optimizing `statusline-command.sh` into a single `jq` stream (`[ .cwd, .tokens, .size ] | @tsv`), dropping execution time from ~250ms to ~21ms, and configuring AGY settings to use `statusline-command.sh`. Squeezed `polish-input` memory/IO consumption by seeking to the tail 64KB of `transcript.jsonl` rather than reading multi-megabyte files into memory. Hardened payload parsing for camelCase / generic prompt dicts, handled null content steps gracefully, and supported `.agents` path detection in standalone `_settings_merge.py`. All 32 polish tests passing. Live verified without errors.
- [x] feat-026: prompt polish rule ships to AGY only, and the AGY statusline renders again. The rule lives in `agents/antigravity-rules.md`; `install-agents-md.sh` appends it to the Gemini block only, so Claude, Codex and Kiro get the shared rules without it (they polish via the hook). The statusline was blank because AGY writes the JSON payload but never closes stdin, so `input=$(cat)` (and jq) blocked until AGY killed it (`signal: killed`). `statusline-command.sh` now stops reading when the top-level JSON object closes. `install_statusline` keeps the object-form `statusLine` for AGY (a live session runs it; the earlier boolean-schema theory was wrong) and now refreshes the installed script copy when settings already point at it, so fixes reach existing installs.
- [x] feat-027: `codex-kiro` now works like `claude-kiro`: plain `codex` on the normal `~/.codex` home with the gateway passed as `-c` overrides. The old alias set `CODEX_HOME=~/.codex-kiro`, which hid every rule, hook and skill installed into `~/.codex`. `setup-codex` writes only the alias, `remove-codex` never deletes a Codex home (it used to `rm -rf` the codex-kiro home, which would have wiped `~/.codex` once they were shared), and `status` reads the alias. `~/.codex-kiro` was removed. The alias defaults to `gpt-5.6-sol` at medium reasoning, the model the old profile pinned.
- [x] feat-028: polish-input stopped replying instead of rewriting. Under `claude-kiro` the hook inherits `ANTHROPIC_BASE_URL` and polishes through the kiro gateway, whose own system prompt made the model answer short prompts as chat ("I can't discuss that.", "I'm Kiro…"). The engine now sends the prompt inside `<text>` tags with a copy-editor system prompt and strips the tags from the reply. A guard in `polish.py` drops outputs that are multi-line, too long, or share under half the words, and logs them as `rejected:` even without `POLISH_DEBUG`.
- [x] feat-029: agy said "not logged in" in macmini tmux panes but not in Terminal.app. Its 2026-10-01 build uses file token storage when `SSH_CONNECTION` is set, and tmux copies that variable into the session on any SSH attach, so new panes inherited it. `setup-host.sh`'s tmux step moved to `scripts/setup-tmux-conf.sh`, which on macOS also sets `update-environment` without `SSH_CONNECTION`; Linux keeps tmux's default, where agy's SSH rule is correct.

### What's In Progress

- Nothing active.

### What's Next

- Run the fresh-session test again on the real hangar and atelier `main` (kiro-cli and gemini
  `AGENTS.md` support is still untested: neither is logged in headless).
- Optional follow-up experiment: repeat exercise 3 at ~10k tokens without the
  "read in full" instruction (design in `position-experiment.md` §13).
- Lecture 5: Why Long-Running Tasks Lose Continuity.


## Blockers / Risks

- **`_lib.sh` pip step fails on Homebrew Python (PEP 668)**: the polish-input SDK install
  (`pip3 install anthropic|google-genai`) is refused as an externally managed environment.
  Pre-existing; found during feat-019. Needs a venv or `pipx`-style install, not
  `--break-system-packages`.

## Decisions Made

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
- [x] feat-025: commits `e4c1f5a` and `93f517c` on `main`;
      `pytest skills/utils/polish-input/tests/test_polish.py` → 32 passed (including tail seek and payload variations);
      `bash scripts/run-tests.sh --fast` → 57 passed, 0 failed; `./init.sh` → all 9 gates passed clean;
      statusline execution reduced from ~250ms to ~21ms with zero recurring errors.

- [x] feat-026: `bash scripts/tests/test_statusline_command.sh` → 8 passed (fails on the old script: 3.1s with stdin open); `bash scripts/tests/test_install_agents_md.sh` → 17 passed; live AGY session in tmux renders `herohsu@VOMAC4294:/tmp` with zero `signal: killed` in the new log; after `install-agents-md.sh`, `[polish]` appears only in `~/.gemini/GEMINI.md`.
- [x] feat-027: commit `6c431bf`; `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh` → 40 passed (4 new codex tests failed on the old code first); live `zsh -i -c 'codex-kiro exec ...'` → provider kiro, answered, and confirmed the `~/.codex` rules load (Fail Loud rule present); `./init.sh` → all gates passed.
- [x] feat-028: `pytest skills/utils/polish-input/tests` → 59 passed (9 new cases failed first, built from today's real bad outputs); live hook through the gateway: "yes" → silent, "use codex-kiro only not codex directly" → "Use codex-kiro only, not codex directly.", the meaning-flip prompt keeps its meaning; `./init.sh` → all gates passed.
- [x] feat-029: `scripts/tests/test_setup_tmux_conf.sh` → 10 OK under bash 5 and `/bin/bash` 3.2 (failed first, script missing); moving the line out of the Darwin branch fails `linux: update-environment not set`; on macmini, with `SSH_CONNECTION` cleared from the session, `agy -p` authenticated via keyring; `./init.sh` → all gates passed.

## Notes for Next Session

Read `AGENTS.md` first — it documents real incidents (bash 3.2 target, symlinked
skills, hook exit codes) that are not obvious from the code alone. Then run
`./init.sh` to see current gate status before making changes.
