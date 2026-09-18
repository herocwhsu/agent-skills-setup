# Session Progress Log

## Current State

**Last Updated:** 2026-09-18
**Active Feature:** none — all tracked features done, `./init.sh` passes clean.
Lecture 2 (harness-creator training) is closed out: Tools (feat-006) and
Environment (feat-005 + feat-007 + feat-008) subsystems both done. One real,
confirmed finding remains deliberately unactioned: `google-generativeai` is
deprecated (successor `google-genai`) — touches shipped code
(`polish_engine.py`), out of scope for this session, see
`docs/harness-creator/lecture-02/summary.md`.

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

### What's In Progress

- Nothing active.

### What's Next

- Nothing queued. Pick up the next unit of work fresh.

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

## Notes for Next Session

Read `AGENTS.md` first — it documents real incidents (bash 3.2 target, symlinked
skills, hook exit codes) that are not obvious from the code alone. Then run
`./init.sh` to see current gate status before making changes.
