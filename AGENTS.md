---
description: Quick reference and operating manual for AI agents working on agent-skills-setup
entrypoint: ./init.sh
verify_command: bash scripts/harness-verify.sh
fast_test_command: bash scripts/run-tests.sh --fast
rules_file: agents/engineering-rules.md
architecture_doc: docs/architecture.md
recent_improvements_doc: docs/improvements/recent-tasks-summary.md
state_layer: [feature_list.json, PROGRESS.md]
---

# AGENTS.md — Agent Operating Manual & Quick Reference

> **Quick Orientation:** Instructions for agents working **on this repository**. The engineering rules this repo *ships* live in [`agents/engineering-rules.md`](agents/engineering-rules.md) and are installed into host files by `scripts/install-agents-md.sh` — editing that file changes every agent on the machine, not just work done here.

## Quick Reference & Cheatsheet

| Domain | Quick Rule / Command | Canonical Reference |
| :--- | :--- | :--- |
| **Startup** | Run `./init.sh` (or `bash scripts/harness-verify.sh`). Read `PROGRESS.md` & `feature_list.json`. | [Startup Workflow](#startup-workflow) |
| **Verification** | Micro-edits: `bash scripts/run-tests.sh --fast --changed`<br>Fast suite: `bash scripts/run-tests.sh --fast`<br>Full gates: `bash scripts/harness-verify.sh` | [Verify](#verify) |
| **Architecture** | Guards: [`harness/guards/`](harness/guards/) (symlinked as `.claude/hooks`)<br>Templates: [`templates/hooks/`](templates/hooks/)<br>Multi-Agent: [`agents/`](agents/) (`kiro/prompts/`, `antigravity-rules.md`)<br>Skills: [`skills/`](skills/) & [`registry.txt`](registry.txt) | [`docs/architecture.md`](docs/architecture.md) |
| **Conventions** | Strictly `WIP=1`. Karpathy rules (Think before coding, Simplicity first, Surgical changes, Fail loud). | [`agents/engineering-rules.md`](agents/engineering-rules.md) |
| **Portability** | macOS `/bin/bash` (3.2) floor + Linux. No `mapfile`, `declare -A`, `;&`. PEP 8 Python naming. | [Shell Portability](#shell-portability) |
| **Git Policy** | Check `git log --oneline` before commit. **NEVER run `git push` without explicit user instruction.** | [Personal Conventions](agents/engineering-rules.md#part-iii-personal-conventions) |
| **Clean State** | Verify 11 gates pass. Run `bash scripts/session-clean.sh`. Update `feature_list.json` & `PROGRESS.md`. | [End of Session](#end-of-session) |
| **Telemetry** | Trend: `bash scripts/trace-evaluation.sh --trend`<br>Check limits: `bash scripts/trace-evaluation.sh --check-thresholds` | [Evaluation Trace](#evaluation-trace) |

Everything below the next two sections cost a real incident. The startup workflow
and definition of done are the exception — added proactively, not from a specific
failure, once `feature_list.json`/`PROGRESS.md` existed to route to.

Each incident section carries one metadata line: what caused it, when it applies,
and what would let it be deleted.

## Startup Workflow

Before writing code:

1. Read this file completely.
2. Read `feature_list.json` for current feature status.
3. Read `PROGRESS.md` for what's done, in progress, and next.
4. Run `./init.sh` (delegates to `scripts/harness-verify.sh`) to confirm the repo is
   clean and verifiable before adding scope. A fresh clone first builds `.venv`;
   the run takes about 5 minutes, so a quiet terminal is not a hang.
5. Work on one feature at a time (WIP=1). Never activate multiple features or combine
   unrelated refactorings. Active features must define an executable verification command.

## Verify

```bash
bash scripts/harness-verify.sh     # registry + tests + secret scan, one exit code
bash scripts/run-tests.sh --fast   # tests only (skips RUN_INTEGRATION=1 cases)
bash scripts/trace-evaluation.sh --trend  # evaluation trace history, multi-agent timeline, token load
```

### Three-Layer Termination Gate

Task completion requires passing through three non-bypassable layers in order:
1. **Layer 1: Static & Syntax** (`mypy .`, `ruff check`, `bash-compat-guard.sh`) — verifies syntax, types, and shell portability (< 2s).
2. **Layer 2: Runtime Unit** (`run-tests.sh --fast`) — verifies isolated component units and scripts (~2 min).
3. **Layer 3: System & E2E** (`harness-verify.sh` / `./init.sh`) — validates all 11 system gates including runtime drift, clean state, hook wiring, and state layer.

Passing Layer 1 or Layer 2 alone never constitutes completion; skipping Layer 3 is considered a premature victory declaration. Run `harness-verify.sh` before claiming work is done. The same gates run as Stop hooks, so skipping it only defers the failure.

## Definition of Done

A change is done only when `./init.sh` passes — not when it looks right. If a gate
is already failing for an unrelated reason, check `feature_list.json` for a
tracked, pre-existing failure before assuming you broke it. Don't claim done
until either it's fixed or you've stated explicitly that it's a known, unrelated
gap. A SKIP (runtime drift, until `install.sh` has run) means that gate checked
nothing: report it as skipped, not as passed.

## End of Session

Before ending a session:

- Update `PROGRESS.md` with what's done, in progress, and next.
- Update `feature_list.json` with new feature status and evidence.
- Run `bash scripts/session-clean.sh` to purge ephemeral caches, sync runtime copies, record session telemetry snapshot, and verify the 5 clean-state invariants.
- The state of the repo — not chat history — is what the next session reads.

### Evaluation Trace

Repository state evolution, multi-agent attribution, duration, and token usage are recorded in `docs/telemetry/evaluation-trace.jsonl`:
- `bash scripts/trace-evaluation.sh --trend`: View recent commit telemetry, multi-agent handoffs, and token trends.
- `bash scripts/trace-evaluation.sh --check-thresholds`: Validate state layer limits (`feature_list.json` <= 250 lines, `PROGRESS.md` <= 150 lines, tokens <= 6,000).
- `bash scripts/session-clean.sh`: Automatically runs threshold checks, purges caches, syncs runtime copies, records a new trace snapshot, and prints the trend table.

## Shell Portability

*Source:* `init-repo.sh` shipped `;&` for months and aborted on every macOS run while CI (bash 5) stayed green. *Applies:* any `*.sh` edit. *Expires:* already enforced by `bash-compat-guard.sh`; delete if the floor moves to bash 5.

Shared scripts must be portable across macOS default `/bin/bash` (3.2) and Linux (Bash 5+). Avoid Bash 4+ features (`;&`, `mapfile`, `declare -A`) or use standard POSIX `sh`.

## Skills symlinks

*Source:* `install_skill` uses `ln -sfn`, so a renamed group dir broke every installed agent. *Applies:* renaming/moving `skills/<group>`. *Expires:* when installs copy instead of symlink (`registry-guard.sh` covers only the registry half).

`skills/<group>` are symlinked into live agent dirs (`~/.claude/skills/`). Renaming or moving skill directories requires running `scripts/install.sh` and updating `registry.txt` in the same commit.

## Hook Conventions

*Source:* `templates/hooks/common/sh-check.sh` exited 1 with `|| true`, so every repo scaffolded from it got a gate that blocked nothing. *Applies:* adding or editing a hook. *Expires:* wiring is enforced by the `*-guard.sh` ratchet in `test_harness_verify.sh`; exit 2 only by each hook's own test.

- **Exit code 2**: Stop hooks must exit 2 to block the agent and surface failure details.
- **`-guard.sh` suffix**: Reserved for whole-repo pass/fail validators wired into `scripts/harness-verify.sh`.

## Python Tooling

*Source:* per-file mypy re-reports imported modules' errors (3× the real count); `ruff check` had 74 pre-existing findings. *Applies:* Python edits. *Expires:* wire `ruff check` once its findings reach 0.

- **Types**: Run `mypy` over the whole repo via `.venv/bin/mypy .` (never per single file).
- **Format**: `ruff.toml` configures `ruff format` only (`ruff check` is unwired).

## Boundaries (scope)

*Source:* `init-repo.sh` overwrote `.claude/hooks/`; tests wrote into real `~/.claude`. *Applies:* running scripts or tests. *Expires:* prompt-only — none of these is mechanically enforced.

- Never point `init-repo.sh` at this repo (it overwrites `.claude/hooks/`).
- Tests must redirect `HOME` to a temporary directory (`~/.claude`, `~/.codex`, `~/.gemini` are touched).
- `install.sh` is routine here — run it without asking, with no `--agent` (it replays
  the saved selection). It refuses to run from a worktree or non-default branch;
  don't pass `--allow-non-main` to get around that.
- Ask before running `scripts/install-agents-md.sh` (rewrites every agent's global rules file).

## Topic Docs

Load a topic doc only when its condition matches the task.

- **`docs/architecture.md`** — layers, invariants, directory layout. *Load when:* changing a subsystem boundary, hook, or gate.
- **`docs/improvements/recent-tasks-summary.md`** — recent milestone summaries, architecture changes, and ROI matrix. *Load when:* reviewing recent changes or understanding repository evolution.
- **`agents/engineering-rules.md`** — the shipped rules. *Load when:* editing them (changes every agent on the machine).
- **`skills/README.md`** — group and subcommand index, skill layout, registry entry types. *Load when:* adding or changing a skill.
- **`docs/archive/features/`** — historical feature specifications. *Load when:* looking up older features (`feat-001` through `feat-040`).
- **`docs/harness-creator/`** — lecture logs and diagnostic tools. *Load when:* doing harness training work.
- **`docs/harness-adoption.md`** — putting this harness into another repo. *Load when:* adopting or refreshing the harness in a repo.
- **`docs/migration.md`** — host upgrades, pyenv, multi-agent dirs. *Load when:* changing interpreters or agent install paths.
