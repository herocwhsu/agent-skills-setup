# Session Progress Log

## Current State

**Last Updated:** 2026-09-15
**Active Feature:** none — all tracked features done, `./init.sh` passes clean

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
- [x] Added `init.sh` as the canonical startup/verification entrypoint (delegates
  to `scripts/harness-verify.sh` — no duplicated logic)
- [x] Added `feature_list.json` and this `progress.md` as real state artifacts

### What's In Progress

- Nothing active.

### What's Next

- Nothing queued. Pick up the next unit of work fresh.

## Blockers / Risks

- None.

## Decisions Made

- **Did not add a fake "one feature at a time" placeholder feature list**:
  this repo is an ongoing multi-skill toolkit, not a single-feature build, so a
  literal `feature_list.json` reflects real completed/queued work instead of a
  templated placeholder. See `AGENTS.md` for this repo's actual working rules.
- **`init.sh` delegates rather than reimplements**: `scripts/harness-verify.sh`
  is already this repo's single source of truth for verification gates (same
  checks the Stop hooks run). A second implementation in `init.sh` would drift
  from it the first time either changed.

Full training-exercise narrative (diagnostic-loop scores, the verification-gap
measurement, the same-model-review lesson): `docs/harness-creator/lecture-01/`.

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

## Evidence of Completion

- [x] Tests pass: `bash scripts/run-tests.sh --fast` → 52 passed, 0 failed
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

## Notes for Next Session

Read `AGENTS.md` first — it documents real incidents (bash 3.2 target, symlinked
skills, hook exit codes) that are not obvious from the code alone. Then run
`./init.sh` to see current gate status before making changes.
