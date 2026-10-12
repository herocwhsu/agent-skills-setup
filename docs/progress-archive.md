# PROGRESS archive

Frozen history moved out of `PROGRESS.md` on 2026-10-04 (Lecture 5). Nothing here is
current state: "Files Modified" stops at feat-014, and "Evidence of Completion" has no entries for
feat-011 to feat-022; its early numbers (8 gates, 53 tests) are from when they were written. Current evidence lives in `feature_list.json`.

This file is the readable history, one paragraph per feature. The structured records that the
state-layer guard validates (description, acceptance criteria, evidence) live in
`docs/archive/features/*.json` and cover feat-001 to feat-055; feat-056 to feat-060 are only here.

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

## Completed Features Archive (feat-001 to feat-060)

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
- [x] feat-017: `harness-verify.sh` now reports a self-skipping gate as `SKIP` and names it
  in the summary. That exposed `secret scan` as a second silent skip (gitleaks and
  osv-scanner were missing); both are now installed and the real scans are clean.
- [x] feat-018: split the global rules. The production gate procedure (old Part IV) is now
  the required `spec-workflow` skill, and `engineering-rules.md` keeps host-neutral triggers
  only (147 → 86 lines). Guarded by `scripts/tests/test_engineering_rules_scope.sh`.
  Deployed to all four hosts via `scripts/install-agents-md.sh`.
- [x] feat-019: polish-input's Gemini backend moved to `google-genai` (API key only). The
  Antigravity OAuth path was removed: it already failed with a 403 scope error, and
  `google-genai` can't use OAuth for the Gemini API. Default model `gemini-1.5-flash`
  (retired) → `gemini-3.5-flash-lite`. Live-tested 2026-10-05 via the `agent-skills-setup:gemini` keychain entry.
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
- [x] feat-030: recorded after the fact for commit `83748b3` (made in a separate session): `polish.py`/`polish_engine.py` accept the agy PreInvocation payload and read Claude Code's macOS keychain credentials; `pytest skills/utils/polish-input/tests` → 60 passed; not re-run against a live agy session.
- [x] feat-031: Lecture 5 cold-start audit. Three subagents and agy found state files lagging git in all three repos; fixed in hangar and atelier, `PROGRESS.md` split into `docs/progress-archive.md`, write-up in `docs/harness-creator/lecture-05/`. Gaps: rebuild time unmeasured, exercises 2–3 not run, no staleness guard.
- [x] feat-032: agy dropped the `apidog`, `progress` and `testing` skills (unquoted `: ` in `description` is invalid strict YAML; Claude Code tolerated it). Quoted them and added `scripts/skill-frontmatter-check.py`, run by `skill-paths-guard.sh`. A headless agy run now logs 0 skill parse errors; `test_skill_paths_guard.sh` 11 passed. agy headless allow rules work as `command(git log)` prefixes (no `*`); documented and installed (read-only list; git log/diff/show excluded since --output writes).
- [x] feat-033: live codex-kiro/agy smoke test with tracer hooks drove six hook fixes: chained and same-command-staged commits now gated, AGY polish on `invocationNum` 0, duplicate hook entries collapsed on install/update, AGY Stop timeout 900s, Codex `apply_patch` edits checked, and the no-clobber key test no longer stores or prints an inherited `KIRO_PROXY_KEY`. Not re-run live after the fixes; Codex repo hooks need per-host trust.
- [x] feat-034: Kiro stopped serving `claude-sonnet-5` (HTTP 400) while `/v1/models` still listed it; `claude-kiro` and `hermes-kiro` now pin `claude-sonnet-5.5`.
- [x] feat-035: `scripts/outside-agent.sh` (`run`/`init`/`status`/`reset`) runs a prompt through the first working outside agent in `~/.agent-skills-setup/outside-agents.conf`; review prefers another model family and exits 3 when only the caller's family answered. `engineering-rules.md` gains `### Outside agents`. The live check found an agy argv-order bug (fixed: `agy --mode plan -p <prompt>`). `init` probes now run from the runtime dir, not the caller's cwd: agy had answered and then likely ran this repo's agy Stop gate (cwd-dependent hang measured). Final review fixes: on rc 0, only a short output that is itself a complete status message (e.g. `Not logged in`, `Usage limit reached`) is read as auth/rate_limit, so answers that merely mention quota/401//login stay ok; an external SIGTERM/SIGINT/SIGHUP to `run` now kills the agent's process group; default `--timeout` is 110s; an ok result clears auth demotion; exit 3 prints one stderr line. Harness-verify and live evidence were recorded on 2026-10-05 before these fixes. `init --force` from the worktree keeps `claude-kiro codex-kiro agy`, and the live review used `codex-kiro` (exit 0). Open: `run` keeps the caller's cwd, so inside a repo that wires agy Stop hooks agy still pays them and may time out; `install-agents-md.sh` not run, so host rule files lack the rule (needs owner approval); real usage-limit messages not observed; no cheap login signal for agy; the runtime drift gate blocks on this host until merge and `install.sh` from main; pre-existing confluence-tree upload flake (random port collision).
- [x] feat-036: rules gain a two-reviewer review (fresh-context subagent plus another model family via `outside-agent.sh`) and a one-pass branch cleanup rule; README gains an "Outside Agents" section with two flow charts. Repo-wide cleanup ran as four parallel fixers (scripts, hooks, skills/utils+infra, other skills and docs) in isolated worktrees: 65 files, +213/-315. Restating and history comments dropped, ~90 doc facts corrected against code (counts, flags, paths, hook events), three duplicates merged (`_own_repo_id` in `lib/lib.sh`, two in confluence-tree/host-optimization). Reviewed both ways: fresh-context subagent (clean, 24 facts and call sites verified) and `codex-kiro` on every changed code line (no behavior change). `lib/lib.sh` changed, so the runtime drift gate also flags `lib.sh` until `install.sh` runs from main. Left on purpose: dated incident comments, hook blocks mirrored byte-for-byte with hangar/atelier, `_repo_id` copies with no canonical home, `_store.sh` dead `linux-headless` branches (dispatch code).
- [x] feat-037: `claude-kiro` hit HTTP 400 from a tmux pane opened 2026-10-01 that still held the old `claude-sonnet-5` alias (a running shell never re-reads `~/.zshrc`); not caused by install/update or the feat-036 cleanup. `claude-kiro` now defaults to `ANTHROPIC_MODEL=claude-sonnet-5.5` and pins Opus/Sonnet/Haiku to Kiro-served IDs; `setup-alias` warns that open shells must re-source.
- [x] feat-038: Lecture 6 follow-up fixes. `init.sh` builds `.venv` from `requirements-dev.txt` on a fresh clone (the first `./init.sh` used to fail the types gate), README and `AGENTS.md` cover the contributor path, run time and SKIP meaning, and the four confluence-tree mock-server tests take a kernel-assigned port for all 11 picks (`limactl`/`wsagent` sit inside the old 49000 range). Verified on a clean copy: 9 gates OK, 1 SKIP (runtime drift under a temp HOME), 4m26s. `init.sh` also refuses a `python3` that differs from `.python-version` and cleans up a build interrupted by INT/TERM/HUP. Left open: unordered `What's Next`, no acceptance-criteria field in `feature_list.json`.
- [x] feat-039: review rule now says when and how much. One review per branch on the cumulative diff before finishing it; none for docs/state/test-only changes, one subagent for ordinary code, two reviewers (plus another model family) for hooks, gates, shipped rules, install scripts and permission/security/data/contract changes. Reviewers get repo read access, the original request and the gate commands, not the author's reasoning. README and `docs/architecture.md` updated. `install-agents-md.sh` was run after owner approval (all four host files refreshed, only the Reviewing line changed). Open: the tiers rest on two data points, so record defect found yes/no over about ten reviews.
- [x] feat-040: Lecture 7 training (why agents overreach and under-finish). Enforced WIP=1 and completion evidence in `state-layer-guard.sh` (17/17 passed); codified WIP=1 in `AGENTS.md`; restructured `What's Next` in `PROGRESS.md` into an ordered queue with verification commands, resolving the open items from Lecture 6; created `docs/harness-creator/lecture-07/` documentation and comparison experiment (-31% LOC with zero scope creep).
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
- [x] feat-051: Relocate Kiro workflow prompts from prompts/ to agents/kiro/prompts/. Relocated root prompts/ to agents/kiro/prompts/ via git mv. Atomically updated install_kiro_prompts and uninstall_kiro_prompts in scripts/_lib.sh to source from agents/kiro/prompts/. Added automated test suite scripts/tests/test_kiro_prompts.sh verifying isolated mock home installations, path substitutions, and uninstalls against both mock repo and live repo (5/5 checks passed). Updated docs/architecture.md. Verified with run-tests.sh --fast (79/79 passed) and all 11 gates in harness-verify.sh.
- [x] feat-052: State layer feature archival to docs/archive/features/. Partitioned 40 historical completed features (feat-001 through feat-040) into docs/archive/features/archive-feat-001-040.json, reducing feature_list.json from 513 lines to 218 lines. Extended .claude/hooks/state-layer-guard.sh to validate archive_references, checking file existence, JSON validity, features schema, and unevidenced completion across both active and archived features with 3-part diagnostics. Added 4 new test cases to .claude/hooks/tests/test_state_layer_guard.sh (40/40 passed under both bash 5 and macOS /bin/bash 3.2). Verified run-tests.sh --fast (79/79 passed) and all 11 gates in harness-verify.sh.
- [x] feat-053: Elevate active repo guard rails to universal harness/guards/. Elevated all 16 guard rails and 12 guard test suites from .claude/hooks/ to agent-agnostic harness/guards/ with backward-compatible relative symlink .claude/hooks -> ../harness/guards. Updated harness-verify.sh, setup-git-hooks.sh, .agents/hooks.json, .codex/hooks.json, run-tests.sh, resolve_test_targets.py, and documentation in docs/architecture.md. Added harness/ to REPO_SUBDIRS in skill_path_var_check.py. Verified run-tests.sh --fast (79/79 passed) and all 11 gates in harness-verify.sh.
- [x] feat-054: Automated evaluation trace loop and trend reporter. Implemented scripts/trace_evaluation.py and scripts/trace-evaluation.sh supporting snapshot recording to docs/telemetry/evaluation-trace.jsonl, formatted --trend historical analysis, --check-thresholds for state layer token bloat detection (feature_list.json > 250 lines, PROGRESS.md > 150 lines), and --json export. Created automated test suite scripts/tests/test_trace_evaluation.sh (9/9 passed). Fast test suite runs 80/80 passed with zero failures.
- [x] feat-055: Wire evaluation trace telemetry into session-clean.sh and AGENTS.md base workflow. Integrated scripts/trace-evaluation.sh snapshot recording and --trend display into scripts/session-clean.sh, added state layer threshold checks during handoffs, extended scripts/tests/test_session_clean.sh (8/8 passed), and documented commands in AGENTS.md Quick Reference and End-of-Session workflow.
- [x] feat-056: Auto duration delta calculation, process tree agent detection, and Markdown trace dashboard. Upgraded `scripts/trace_evaluation.py` to auto-calculate elapsed duration since previous trace entries when `--duration-ms` is omitted, inspect process tree ancestry in `detect_agent()` via `get_process_ancestors()` (eliminating ambiguous directory checks), format times human-readably (ms, s, m, h), and auto-generate `docs/telemetry/SUMMARY.md` Markdown dashboard table on record. Added tests in `scripts/tests/test_trace_evaluation.sh` (12/12 passed).
- [x] feat-057: Subagent telemetry tracking (self subagents and outside agents) and independent review verification. Added execution logging (`_log_outside_run`) to `scripts/outside_agent.py` recording runs to both state and local telemetry (`docs/telemetry/outside-agent-runs.jsonl`, gitignored). Implemented subagent tracking in `scripts/trace_evaluation.py` (`--self-subagents`, `--outside-subagents`, auto-detection via `auto_detect_outside_runs`, defensive parsing against malformed lines and naive/aware datetimes, cross-platform Python 3.9+ compatibility). Updated `SUMMARY.md` and CLI trend table with Subagents column. Added unit tests in `scripts/tests/test_trace_evaluation.sh` (16/16 passed across all timezones) and `tests/test_outside_agent.py` (92 passed, 1 skipped). Adversarially reviewed across 5 iterative rounds with both self subagents and outside independent agents (Claude Code `outside-agent.sh`) achieving CLEAN PASS.
- [x] feat-058: Autonomous ratchet loop runner, goal specifications, and review iteration flow. Standardized goal specifications under docs/goals/ (TEMPLATE.md) defining machine-verifiable acceptance criteria, fair-game and hands-off scopes, and stopping conditions. Promoted ratchet_loop into scripts/ratchet_loop_runner.py and scripts/ratchet-loop.sh CLI runner with support for --goal-file, --active-feature, --review-diff, and --demo modes. Implemented automated verification, independent Checker review evaluation (via outside-agent.sh or custom checkers), automated rollback on regression, and circuit breakers. Added unit tests in tests/test_ratchet_loop_runner.py (5/5 passed) and scripts/tests/test_ratchet_loop.sh (6/6 passed across macOS system Python 3.9 and Python 3.14). All fast test suites and 11 harness gates pass.
- [x] feat-059: State layer context bloat remediation and feature archival (feat-051 through feat-055). Partitioned completed features feat-051 through feat-055 into docs/archive/features/archive-feat-051-055.json, updated feature_list.json archive_references, and pruned historical training decisions from PROGRESS.md into docs/progress-archive.md. State layer tokens reduced below 6,000 threshold (OK status in trace evaluation).
- [x] feat-060: Graph Engineering DAG runner, state machine orchestration, and Lecture 14 closing. Authored comprehensive Lecture 14 study materials (summary.md, progress-detail.md, code/graph.md). Implemented zero-dependency StateGraph engine in docs/harness-creator/lecture-14/code/graph_engine.py with checkpointer persistence, human-in-the-loop pause, and conditional rollback routing. Promoted to production CLI runner in scripts/graph_runner.py and scripts/graph-runner.sh. Added automated unit tests in docs/harness-creator/lecture-14/code/test_graph_engine.py (5/5 passed), tests/test_graph_runner.py (3/3 passed), and scripts/tests/test_graph_runner.sh (3/3 passed). Audited by independent adversarial subagent with CLEAN PASS verdict. Verified with run-tests.sh --fast (86/86 passed) and all 11 gates in harness-verify.sh.

## Archived Decisions (Lectures 1–3)

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
