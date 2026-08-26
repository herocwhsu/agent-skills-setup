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

## The `-guard.sh` suffix is load-bearing

`scripts/tests/test_harness_verify.sh` globs `.claude/hooks/*-guard.sh` and fails
if any of them is missing from `harness-verify.sh`. So the suffix is a claim: *this
hook is a validator, it answers pass/fail, and an on-demand verify must run it.*

`commit-evidence.sh` is a Stop hook that is deliberately **not** a `-guard`. It
validates nothing — it prints a commit range once and blocks for attention,
mutating a state file in `.git/` as it goes. Wiring it into `harness-verify.sh`
would be worse than pointless: the verify run would consume the state, leaving the
real Stop hook silent, and the verify would exit 1 after every commit. Its test
asserts it stays out.

Name a new hook `-guard.sh` only if it is a pass/fail check over the whole repo.

## Python: formatter and types yes, linter no

`ruff.toml` sets `line-length = 100` for `ruff format` only. `ruff check` is
deliberately unwired — 74 pre-existing findings, so gating an edit on it would block
over unrelated code.

`mypy.ini` drives a type gate that runs at Stop (`.claude/hooks/types-guard.sh`) and
is clean, so keep it clean. It is not `--strict`: 103 of 233 functions carry no
annotations, and `disallow_untyped_defs` would have made the gate suppressed from
birth.

Run mypy over the **whole tree**, never per file. Invoking it on one file
re-reports every error living in the modules it imports — `mypy polish.py` shows 11
errors that are all in `polish_engine.py`, which is how a 15-error baseline gets
miscounted as 30.

Neither config lives in `pyproject.toml`: osv-scanner treats that as a dependency
manifest and `secret-scan.sh` special-cases this repo's "no package sources found"
result, so adding one would change a Stop hook as a side effect of a typing choice.

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
