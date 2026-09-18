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
manifest, and adding one would change `secret-scan.sh`'s Stop-hook behavior as a
side effect of a typing choice.

`requirements-dev.txt` **is** a real, scanned manifest — it exists on purpose,
generated via `.venv/bin/pip freeze` from this repo's own isolated dev venv (not
the ambient/shared pyenv environment other projects on this machine also use).
`secret-scan.sh`'s osv-scanner step now genuinely scans it and blocks (exit 2)
if a real CVE turns up in a pinned version, same as a real gitleaks finding —
this is a deliberate, accepted cost: a newly-published CVE against something in
that file can block a session here until the pin is bumped. `.claude/hooks/types-guard.sh`
and `scripts/run-tests.sh` prefer `.venv/bin/mypy` / `.venv/bin/python3 -m pytest`
when the venv exists, falling back to bare `mypy`/`python3` otherwise — every
other `python3` call site in this repo (installer scripts, credential helpers,
hook templates shipped to other repos) intentionally still resolves from the
ambient PATH, since that code runs on other people's machines, not just this
repo's own dev loop.

Use `ast.parse` rather than `py_compile` to syntax-check — `py_compile` litters
`__pycache__` beside every file it touches.

## Boundaries (scope)

- Never point `init-repo.sh` at this repo; it overwrites `.claude/hooks/`.
- Tests must redirect `HOME` to a temp dir. Several scripts write to `~/.claude`,
  `~/.codex`, `~/.gemini`, and `~/.kiro`.
- Never write `AGENTS.override.md` — Codex prefers it over `AGENTS.md`, so it would
  shadow whatever the user put there. Enforced: `.claude/settings.json` denies
  `Write`/`Edit` on `AGENTS.override.md` under any user's home dir.
- Ask before running `scripts/install-agents-md.sh` or `install.sh`: both write
  outside the repo and change agent behavior for every project. Advisory only —
  a settings.json `ask` rule matching one invocation form (`bash scripts/x.sh`)
  is trivially bypassed by any other (`./scripts/x.sh`, `sh scripts/x.sh`, an
  absolute path), so this is not enforced and was deliberately not attempted as
  a permission rule.
