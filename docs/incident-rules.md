# Incident rules

Each rule below cost a real incident. `AGENTS.md` carries the one-line rule; this file keeps
the incident, when it applies, and what would let it be deleted. Load the section that
matches the edit you are about to make.

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
