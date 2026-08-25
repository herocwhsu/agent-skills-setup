# AGENTS.md

Instructions for agents working **on this repository**. The engineering rules this
repo *ships* live in `agents/engineering-rules.md` and are installed into host
files by `scripts/install-agents-md.sh` — editing that file changes every agent on
the machine, not just work done here.

Everything below cost a real incident. Nothing here restates what `ls`, `README.md`,
or the code already tells you.

## Verify

```bash
bash scripts/harness-verify.sh     # registry + tests + secret scan, one exit code
bash scripts/run-tests.sh --fast   # tests only (skips RUN_INTEGRATION=1 cases)
```

Run `harness-verify.sh` before claiming work is done. The same gates run as Stop
hooks, so skipping it only defers the failure.

## Target shell is bash 3.2, not bash 5

macOS ships bash 3.2.57 as `/bin/bash` and that is the floor. No `;&` case
fallthrough, no `mapfile`/`readarray`, no `declare -A`.

CI runs `ubuntu-latest`, where bash 5 accepts all three — so `bash -n` passing in CI
proves nothing about portability. `init-repo.sh` shipped `;&` for months and aborted
partway through on every macOS run; CI stayed green the whole time.
`scripts/tests/test_init_repo.sh` greps for these constructs for that reason.

## Skills are symlinked into the live agent dirs

`install_skill` in `scripts/_lib.sh` uses `ln -sfn`, so `~/.claude/skills/<group>`
points *into this working tree*. Renaming or moving a `skills/<group>/` directory
breaks every installed agent until `scripts/install.sh` re-runs, and
`registry.txt` has to move in the same commit — a Stop hook validates it.

## Hooks block with exit 2

Exit 2 is the only code Claude Code feeds back to the agent. Exit 1 surfaces an
error without blocking; auto-fixers exit 0. `hooks/common/sh-check.sh` used exit 1
plus `|| true` and therefore blocked nothing while presenting as a gate — every repo
scaffolded from it inherited a no-op. When adding a gate, assert the exit code in a
test rather than assuming it.

## Python: formatter yes, linter no

`ruff.toml` sets `line-length = 100` for `ruff format` only. `ruff check` is
deliberately unwired — 74 pre-existing findings, so gating an edit on it would block
over unrelated code. Not `pyproject.toml`: osv-scanner treats that as a dependency
manifest and `secret-scan.sh` special-cases this repo's "no package sources found".

Use `ast.parse` rather than `py_compile` to syntax-check — `py_compile` litters
`__pycache__` beside every file it touches.

## Boundaries

- Never point `init-repo.sh` at this repo; it overwrites `.claude/hooks/`.
- Tests must redirect `HOME` to a temp dir. Several scripts write to `~/.claude`,
  `~/.codex`, `~/.gemini`, and `~/.kiro`.
- Never write `AGENTS.override.md` — Codex prefers it over `AGENTS.md`, so it would
  shadow whatever the user put there.
- Ask before running `scripts/install-agents-md.sh` or `install.sh`: both write
  outside the repo and change agent behavior for every project.
