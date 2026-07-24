---
title: local pre-commit shell gate via .claude
date: 2026-07-24
status: approved
---

# local pre-commit shell gate via .claude

A `PreToolUse` hook in this repo's `.claude/` that blocks an agent `git commit`
when any staged `*.sh` file fails `bash -n` or `shellcheck --severity=error`.

## Problem

Shell lint in `agent-skills-setup` is advisory and Claude-edit-only:

- `hooks/common/sh-check.sh` runs on `PostToolUse` edits, and its shellcheck line
  ends in `|| true` — it never blocks. Only `bash -n` blocks, and only when *Claude*
  is the editor. A human or subagent commit bypasses it entirely.
- CI (`.github/workflows/test.yml`) runs `install.sh` + `run-tests.sh --fast` but
  does **not** run shellcheck. A broken `lib/*.sh` that no test sources can reach
  `main`.
- The repo authors `hooks/common/sh-check.sh` for *other* repos to copy, but never
  wired it into its own `.claude/` (`.claude/` is empty). It does not dogfood.

Result: a script with a syntax error or a real shellcheck error can be committed.

## Goals

- Block an agent `git commit` locally when staged shell is broken.
- Gate the **staged blob**, not the working tree, so what lands is what was checked.
- No hard dependency: `bash -n` always runs; shellcheck runs when present.
- Dogfood inside `agent-skills-setup` only.

## Non-Goals

- CI enforcement (explicitly out of scope for this change).
- Rolling the gate into what `install.sh` sets up for other repos (future change).
- Auto-formatting (`shfmt`) — enforce correctness, not style.
- Gating extensionless shebang scripts (v1 checks `*.sh` only).
- Blocking human `git commit` run outside the agent (a Claude hook cannot see that;
  it is a known limitation, not a goal here).

## Mechanism

`.claude/settings.json` (new) registers a `PreToolUse` hook matching `Bash`, pointing
at `.claude/hooks/precommit-sh-check.sh`. Claude Code passes the tool input as JSON on
stdin; the hook exits 0 to allow, exits 2 to block (stderr message shown to the agent).

Hook logic:

1. Read `tool_input.command` from stdin JSON.
2. Allow (exit 0) unless the command is a real `git commit` — exclude `--dry-run`,
   `--help`, and commands where "commit" appears only inside the message string.
3. Collect staged shell: `git diff --cached --name-only --diff-filter=ACM`, keep `*.sh`.
   None → allow.
4. For each staged file, check the **staged content**:
   - `git show ":$FILE" | bash -n -` — syntax; failure blocks.
   - `git show ":$FILE" | shellcheck --severity=error -` (if shellcheck present);
     failure blocks.
5. Any failure → collect all offenders, print `FILE: reason` to stderr, exit 2.
   All clean → exit 0.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| What to check | Staged blob via `git show :FILE` | If a broken version is staged then the working tree is fixed without re-staging, a disk check passes while the broken blob commits. Gate what lands. |
| Severity | `shellcheck --severity=error` | A blocking gate stops broken/buggy shell, not style nits. Warnings stay advisory in the edit-time hook. |
| shellcheck missing | Run `bash -n` only, notice, do not block on absence | No hard tool dependency; syntax is always gated. |
| File scope | `*.sh` only | Matches the existing hook's scope; extensionless scripts are a noted limitation. |
| commit detection | Parse the command; skip `--dry-run`/`--help`/message-only matches | Avoid false blocks on `git status`, `echo "commit"`, etc. |

## Testing

- `shellcheck` on `precommit-sh-check.sh` itself.
- Unit cases feeding synthetic stdin JSON:
  - clean staged `.sh` → exit 0.
  - staged file with a `bash -n` syntax error → exit 2, names the file.
  - staged file with a shellcheck `error` → exit 2, names the file.
  - shellcheck-`warning`-only staged file → exit 0 (not blocked).
  - non-commit Bash (`git status`, `ls`) → exit 0, untouched.
  - `git commit --dry-run` → exit 0.
  - working-tree fixed but broken blob still staged → exit 2 (proves blob-based check).
  - shellcheck absent (PATH stubbed) → syntax still gated, shellcheck skipped.

## Files

| Action | Path | Purpose |
|---|---|---|
| Create | `.claude/settings.json` | Register PreToolUse Bash hook |
| Create | `.claude/hooks/precommit-sh-check.sh` | The gate |
| Create | `.claude/hooks/tests/test_precommit_sh_check.sh` | Unit cases above |
