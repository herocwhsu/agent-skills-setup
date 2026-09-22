# Session Progress Log

## Current State

**Last Updated:** 2026-09-21
**Active Feature:** none — all tracked features done, `./init.sh` passes clean.
**Lecture 2 (harness-creator training) is now fully closed**: Tools
(feat-006), Environment (feat-005 + feat-007 + feat-008), the exclusion-test
exercise (feat-009, non-null on the second attempt), and the
affordance-analysis exercise (feat-010) are all done. One real, confirmed
finding remains deliberately unactioned: `google-generativeai` is deprecated
(successor `google-genai`) — touches shipped code (`polish_engine.py`), out
of scope for this session, see `docs/harness-creator/lecture-02/summary.md`.

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
- [x] Added `feature_list.json` and this `progress.md` as real state artifacts
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

### What's In Progress

- Nothing active.

### What's Next

- Ready for next tasks or Lecture 3.


## Blockers / Risks

- **`google-generativeai` (pinned in `requirements-dev.txt`, used by
  `skills/utils/polish-input/lib/polish_engine.py`'s Gemini backend) is
  deprecated** — confirmed via PyPI directly: legacy status, support ended
  2025-11-30, successor is `google-genai`. Not a blocker (still installs and
  works; osv-scanner reports no CVE against it), but a real migration is
  owed eventually. Not done this session — touches shipped code, a
  different-shaped change than this session's dev-tooling scope.

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
- **`google-generativeai` deprecation confirmed but not migrated**: real,
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
- `init.sh`, `feature_list.json`, `progress.md` — added as this repo's state
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
  this `progress.md` — feat-009 (exclusion-test attempt 2, non-null result,
  confound recorded, correlation-vs-causation distinction made explicit).
  No repo functionality changed by feat-009 itself — the shellcheck gates
  built during the test lived only in the disposable `/tmp/exclusion-test-v2/`
  variant directories, not in this repo.
- `docs/harness-creator/lecture-02/summary.md`,
  `docs/harness-creator/lecture-02/progress-detail.md`, `feature_list.json`,
  this `progress.md` — feat-010 (affordance analysis, Lecture 2 closed out).
  No repo functionality changed — classification exercise only.

## Evidence of Completion

- [x] Tests pass: `bash scripts/run-tests.sh --fast` → 53 passed, 0 failed
- [x] Type check clean: `python3 -m mypy --config-file mypy.ini .` → Success:
      no issues found in 27 source files
- [x] `./init.sh` → all 7 gates pass (registry, types, tests, skill paths,
      cred backends, hook wiring, secret scan)
- [x] Registry validates: `bash scripts/validate-registry.sh` → clean
- [x] Independently verified by a second agent (`kiro-cli`, no shared context):
      given only `AGENTS.md` + `feature_list.json` + `progress.md`, correctly
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

## Notes for Next Session

Read `AGENTS.md` first — it documents real incidents (bash 3.2 target, symlinked
skills, hook exit codes) that are not obvious from the code alone. Then run
`./init.sh` to see current gate status before making changes.
