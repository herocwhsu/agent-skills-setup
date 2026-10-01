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
- **agy, kiro-cli, gemini:** could not be tested headless (not logged in). Unverified.

## Review

Ask a different model family for review and confirm its claims mechanically: the
same-model review in Lecture 1 missed a test that passed whether or not the feature
worked, and a different model's confident claims in Lecture 2 were false twice.
Finish with the fresh-session test: a session with no context should answer what the
repo is, how it is laid out, how to run it, how to verify it and where work stands.

## Known gaps in the shared hooks

- The old `secret-scan` template ran gitleaks as `cd "$REPO_ROOT"; --source .` so
  fingerprints match a committed `.gitleaksignore`. The shared version passes an
  absolute `--source`. A repo that adds `.gitleaksignore` needs that change, applied
  to every copy at once.
- atelier's `py-guard.sh` and `ts-guard.sh` gate on `git diff HEAD`, not the
  merge-base, so a commit-then-stop session skips them. They also join two file lists
  with `+=` and no newline. Neither was changed here.
