# Adopting the harness in another repo

What Lectures 1 to 4 produced, and how to put it into a repo that is not this one.
Adapt to the repo; do not run `scripts/init-repo.sh --force` over a repo that already
has hooks, because its templates can be older than what the repo has learned.

## Look first

Before adding anything, list what the repo already has: `.claude/hooks/`, a verify
script, CI jobs, instructions file. Add only what is missing. In hangar and atelier
the hooks were already ahead of the templates (turn-scope gating, stderr and exit 2),
which is why the templates were refreshed from them.

## What to add, in order

| Piece | What | Skip when |
|---|---|---|
| `AGENTS.md` | Router, at most 100 lines: purpose, hard constraints, Startup, Verify, Definition of Done, End of Session, Topic Docs with *Load when* conditions. Move long hook or design notes to `docs/`. | Never. |
| `CLAUDE.md` | One line, `@AGENTS.md`, so Claude Code and other agents share one source. | The repo has no `CLAUDE.md`: Claude Code reads `AGENTS.md` on its own. |
| `init.sh` | Delegates to the repo's real gates and checks the state files exist. It adds no gate logic. | Never. |
| `PROGRESS.md` | Current state, in flight, next. | Never. |
| `feature_list.json` | Catalog with evidence per entry. | The repo has no feature catalog (an infra repo, for example). |
| Hook tests | A `scripts/test-hooks.sh` run in CI, using a throwaway git repo per case. | The repo has no hooks. |
| `.python-version` and `.venv` | Pin the interpreter and fail loud on drift. | The repo has no Python project. |

## Rules that cost an incident

- **Test the test.** A hook test is valid only if it fails when the hook is broken.
  Mutate each hook (flip an exit code, force a gate open or shut) and watch the test
  go red. Stub scanners on PATH, or a missing tool turns every gate case into a pass.
- **Verify entrypoints must mean something.** A turn-scoped Stop hook run on a clean
  tree scans nothing, so `init.sh` calls the real checks (pre-commit, builds, tests)
  and not the Stop hooks.
- **Say what a gate skipped.** A gate whose tool is absent exits 0. Report that as
  SKIP, never as OK.
- **Do not copy repo-specific hooks.** `registry-guard`, `skill-paths-guard`,
  `credential-backend-guard`, `hook-wiring-guard` and `precommit-sh-check` check this
  repo's own structure.

## Agent support for a project `AGENTS.md`

Checked 2026-10-01 with a canary word in a throwaway repo:

- **Claude Code:** reads `AGENTS.md` alone, and through `CLAUDE.md` containing
  `@AGENTS.md`. Verified.
- **Codex CLI:** documented to read it; not installed here, so not run.
- **agy:** reads `AGENTS.md` alone and through `CLAUDE.md` containing `@AGENTS.md`.
  Verified headless on 2026-10-02. Over SSH or tmux started from an SSH attach, run it
  as `env -u SSH_CONNECTION agy ...`: with `SSH_CONNECTION` set, agy ignores its keychain
  login and reports "not logged into Antigravity".
- **kiro-cli, gemini:** could not be tested headless (not logged in; gemini's CLI is no
  longer supported for individual accounts). Unverified.

## Review

Ask a different model family for review and confirm its claims mechanically: the
same-model review in Lecture 1 missed a test that passed whether or not the feature
worked, and a different model's confident claims in Lecture 2 were false twice.
Finish with the fresh-session test: a session with no context should answer what the
repo is, how it is laid out, how to run it, how to verify it and where work stands.

## Things the shared hooks learned late

- `secret-scan` runs gitleaks as `cd "$REPO_ROOT"; --source .`. An absolute
  `--source` is baked into each finding's fingerprint and can never match a committed
  `.gitleaksignore` entry. Fixed in all three copies together, with a test.
- A turn-scoped hook must measure against the merge-base, and count untracked files.
  atelier's `py-guard` and `ts-guard` used `git diff HEAD`, which skipped both a
  commit-then-stop session and a brand-new file; four test cases failed on the old
  code before the fix.

## State files rot at session boundaries

A cold-start rebuild of all three repos found cheap rebuilds but stale state: a merged
harness still marked unmerged, a parallel session's commit unrecorded, and one `Active
Feature` line added per session instead of replaced. Put this in the repo's End of Session:
overwrite "Current state" and "In flight", append history under dated sections, and write
owner decisions into the repo (a decision only in chat or memory is invisible to the next
agent). No staleness gate is shipped: it would also gate automerged PRs.
