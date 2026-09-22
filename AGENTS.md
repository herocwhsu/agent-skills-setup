# AGENTS.md

Instructions for agents working **on this repository**. The engineering rules this
repo *ships* live in `agents/engineering-rules.md` and are installed into host
files by `scripts/install-agents-md.sh` — editing that file changes every agent on
the machine, not just work done here.

Everything below the next two sections cost a real incident. The startup workflow
and definition of done are the exception — added proactively, not from a specific
failure, once `feature_list.json`/`progress.md` existed to route to.

## Startup Workflow

Before writing code:

1. Read this file completely.
2. Read `feature_list.json` for current feature status.
3. Read `progress.md` for what's done, in progress, and next.
4. Run `./init.sh` (delegates to `scripts/harness-verify.sh`) to confirm the repo
   is in a clean, verifiable state before adding scope.

## Verify

```bash
bash scripts/harness-verify.sh     # registry + tests + secret scan, one exit code
bash scripts/run-tests.sh --fast   # tests only (skips RUN_INTEGRATION=1 cases)
```

Run `harness-verify.sh` before claiming work is done. The same gates run as Stop
hooks, so skipping it only defers the failure.

## Definition of Done

A change is done only when `./init.sh` passes — not when it looks right. If a gate
is already failing for an unrelated reason, check `feature_list.json` for a
tracked, pre-existing failure before assuming you broke it. Don't claim done
until either it's fixed or you've stated explicitly that it's a known, unrelated
gap.

## End of Session

Before ending a session:

- Update `progress.md` with what's done, in progress, and next.
- Update `feature_list.json` with new feature status and evidence.
- The state of the repo — not chat history — is what the next session reads.

## Shell Portability

Shared scripts must be portable across macOS default `/bin/bash` (3.2) and Linux (Bash 5+). Avoid Bash 4+ features (`;&`, `mapfile`, `declare -A`) or use standard POSIX `sh`.

## Skills symlinks

`skills/<group>` are symlinked into live agent dirs (`~/.claude/skills/`). Renaming or moving skill directories requires running `scripts/install.sh` and updating `registry.txt` in the same commit.

## Hook Conventions

- **Exit code 2**: Stop hooks must exit 2 to block the agent and surface failure details.
- **`-guard.sh` suffix**: Reserved for whole-repo pass/fail validators wired into `scripts/harness-verify.sh`.

## Python Tooling

- **Types**: Run `mypy` over the whole repo via `.venv/bin/mypy .` (never per single file).
- **Format**: `ruff.toml` configures `ruff format` only (`ruff check` is unwired).

## Boundaries (scope)

- Never point `init-repo.sh` at this repo (it overwrites `.claude/hooks/`).
- Tests must redirect `HOME` to a temporary directory (`~/.claude`, `~/.codex`, `~/.gemini` are touched).
- Ask before running `scripts/install-agents-md.sh` or `install.sh` (modifies external host files).

