# Session Progress Log

## Current State

**Last Updated:** 2026-10-08
**Active Feature:** none. feat-041 closed out; `./init.sh` passes all gates.
**Harness lectures:** 1–7 closed (`docs/harness-creator/lecture-0N/summary.md`). Lecture 7
(why agents overreach and under-finish) closed: WIP=1 and executable verification enforced
in `state-layer-guard.sh`; `What's Next` ordered by priority with verification commands.
Lecture 5 open items: rebuild time never
measured, no staleness guard, `What's Done` still ~140 lines (`docs/harness-creator/lecture-05/summary.md`).

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

### What's In Progress

- Nothing active.

### What's Next

**Prioritized Technical Queue (WIP=1):**
1. **Scope Stop gate tests to changed files:** Reduce stop hook latency from ~3m to <10s on single-file edits.
   - *Verification:* `bash scripts/run-tests.sh --fast --changed` and `bash .claude/hooks/tests-guard.sh`.
   - *Plan:* `docs/harness-creator/lecture-07/code/task-atomization-plan.md`.
2. **Fix `_lib.sh` pip step under Homebrew Python (PEP 668):** Replace `--break-system-packages` with isolated venv/pipx.
   - *Verification:* `bash scripts/tests/test_hook_wiring.sh` without pip PEP 668 warnings.
3. **Smoke test verification:** Re-run live `codex-kiro` and `agy` smoke tests against feat-033 fixes; trust repo hooks in Codex on each host.
   - *Verification:* `outside-agent.sh run --purpose review` exits 0.
4. **Fresh-session cross-repo tests:** Run fresh-session test on real `hangar` and `atelier` `main` once logged in headless.
5. **Position experiment scaling:** Run follow-up experiment at ~10k tokens without "read in full" instruction (`position-experiment.md` §13).

**Pending Owner Decisions (Blocked on Human):**
- **daily-ai-video-pipeline:** Decide whether to create private remote GitHub repo or remain local.
- **Hermes cleanup:** Decide whether to drop residual `~/.hermes` configs from `skills/infra/kiro-gateway` or keep for other hosts.
- **Handy branch:** Decide if `local/zh-tw-default` needs further integration or remains fork-only.


## Blockers / Risks

- **`_lib.sh` pip step fails on Homebrew Python (PEP 668)**: the polish-input SDK install
  (`pip3 install anthropic|google-genai`) is refused as an externally managed environment.
  Pre-existing; found during feat-019. Needs a venv or `pipx`-style install, not
  `--break-system-packages`.

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
