---
title: outside-agent selection
date: 2026-10-05
status: draft
---

# outside-agent selection

One script that picks a working outside agent (another CLI agent, possibly a
different model family) for delegation or review, instead of each agent guessing
from prose and memory.

## Problem

Which outside agents work differs by machine and changes over time. On this Mac
(probed 2026-10-05 with a "Reply with exactly: OK" prompt, 90s cap):

| Candidate | Result |
|---|---|
| `claude-kiro` (zsh alias) | OK, 12s, via kiro-gateway `localhost:7788` |
| `codex-kiro` (zsh alias) | OK, 13s, `gpt-5.6-sol` via the gateway |
| `agy` | OK, 14s, subscription login |
| `claude` | `Not logged in · Please run /login`, exit 0 |
| `codex` | 401 after 5 retries, 22s |

Facts the design depends on, all observed in that probe:

- Exit codes lie: plain `claude` exits 0 when not logged in.
- Inherited env lies: inside a `claude-kiro` session `ANTHROPIC_BASE_URL` and
  `ANTHROPIC_API_KEY` are set, and plain `claude` answered OK until they were unset.
- Aliases load only in an interactive shell (`zsh -i -c`), which adds iTerm
  escape sequences to output.
- macOS has no `timeout`; `perl -e 'alarm N; exec @ARGV'` works.
- `claude-kiro` and `codex-kiro` share one kiro-gateway quota.

Lecture 1 also showed same-model review is not independent review: a Claude
session reviewed by `claude-kiro` is still Claude reviewing Claude.

## Goals

- Pick the first working candidate per call, from a per-machine list.
- Notice agents appearing or disappearing without a manual reset.
- Skip candidates that hit a usage limit until their quota resets.
- Fail loud when nothing works; never fall back silently to same-model review.

## Non-goals

- Running the caller's own subagent. A shell script cannot invoke a host's Agent
  tool; the rule tells the caller to do that first.
- polish-input backend selection (separate API-call layer; its
  `ClaudeSessionProvider`-first order is a separate known issue).
- Waiting or retrying when every candidate is rate-limited.

## Layout

| File | Where | Tracked |
|---|---|---|
| `scripts/outside-agent.sh` | repo (source of truth) | yes |
| `~/.agent-skills-setup/outside-agent.sh` | flat copy via `install_runtime_dir` | no |
| `~/.agent-skills-setup/outside-agents.conf` | per-machine candidate list | no |
| `~/.agent-skills-setup/state/outside-agents.json` | failure records | no |

A flat copy matches `lib.sh` and `_store.sh`; rules reference the installed path so
every host can call it from any project.

## Candidates

The repo ships a fixed table of known kinds. Each kind defines a pre-check, a run
command, and a quota group. The conf picks which kinds this machine uses and in
what order. An unknown name in the conf fails loud.

| Kind | Pre-check (no tokens) | Run | Quota group | Family |
|---|---|---|---|---|
| `claude-kiro` | alias defined; gateway answers in 1s; proxy key in keychain | `zsh -i -c 'claude-kiro -p …'` | `kiro` | claude |
| `codex-kiro` | same | `zsh -i -c 'codex-kiro exec --skip-git-repo-check …'` | `kiro` | openai |
| `agy` | command exists | `agy -p …` (`--mode plan` for review) | `agy` | gemini |
| `claude` | command exists; `Claude Code-credentials` keychain entry | `env -u ANTHROPIC_* claude -p …` | `claude` | claude |
| `codex` | command exists; `~/.codex/auth.json` exists | `codex exec --skip-git-repo-check …` | `codex` | openai |

Every run strips escape sequences and is bounded by the perl alarm timeout.
`claude`/`codex` always run with inherited provider env unset.

## Conf generation

`install.sh` and `update.sh` call `outside-agent.sh init` after `install_runtime_dir`.

- Conf missing: pre-check every kind, live-probe the ones that pass in parallel
  (60s cap, inherited env cleared), write passing kinds in default order
  `claude-kiro, codex-kiro, agy, claude, codex`, and failed ones as comments:
  ```
  claude-kiro
  codex-kiro
  agy
  # claude    not logged in (2026-10-05)
  # codex     401 (2026-10-05)
  ```
- Conf exists: never rewrite it. Detect again and print the diff
  (`detected but not listed: …; listed but not found: …`).
- `init --force` regenerates from scratch.
- Detection failure never fails install: warn and write what was found. Zero
  found writes a commented empty file.

## Per-call flow

`run` walks the conf order. For each candidate:

1. Skip if its quota group has an active rate-limit record.
2. Run the cheap pre-check every call (gateway down/up is seen immediately).
3. Run the prompt and classify the output:

| Class | Match | Action |
|---|---|---|
| `ok` | real output | return it |
| `auth` | `Not logged in`, `401`, `Unauthorized`, `/login` | next candidate; record; demote to the end for 7 days (still tried last) |
| `rate_limit` | `usage limit`, `quota`, `limit reached` (case-insensitive) | next candidate; skip the quota group until reset |
| `transient` | timeout, gateway unreachable | next candidate; no record |
| `error` | anything else | stop, exit 2, print output |

Rate-limit reset:

- `agy`, `claude`, `codex`: 5 hours after the failure.
- `kiro` group: 00:00 local on the 1st of the next month. Both `*-kiro` kinds
  are skipped together.
- An explicit reset time in the message, if parseable, overrides the default.
  Unparseable means the default.

Bare `429`/`rate limit` wording is not matched as `rate_limit`; it lands in
`error` and stops loudly, by decision, until real messages show it should skip.

## Interface

```
outside-agent.sh run --purpose delegate|review --from claude|openai|gemini \
                     [--timeout 300] [--cwd DIR] [--allow-edits] -- "prompt"
outside-agent.sh init [--force]
outside-agent.sh status          # conf, per-candidate records, reset times
outside-agent.sh reset [kind|group]
```

- stdout: the agent's answer only.
- stderr: one line, e.g.
  `[outside-agent] used=codex-kiro skipped=claude-kiro(rate_limit until 2026-11-01 00:00),claude(precheck)`.
- `--from` is required, never inferred from env.
- `--allow-edits` is required before any candidate gets write or edit permissions.
  Reviews always run read-only.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | success |
| 2 | no candidate succeeded, unknown error, or bad conf; all-rate-limited prints the earliest reset |
| 3 | `--purpose review` succeeded only with a candidate of the caller's own family; not independent |

For review, candidates of the caller's family are tried only after every other
family has failed, and success there returns 3.

## Rule

About four lines added to `agents/engineering-rules.md`:

- Delegating: run your own subagent first; for an outside agent call
  `~/.agent-skills-setup/outside-agent.sh run --purpose delegate`.
- Reviewing: at least one answer must come from a different model family
  (`--purpose review`). Exit 3 is reported as "not independent", never as a pass.
- Exit 2 is reported with its stderr line, not worked around.

Shipping it requires `scripts/install-agents-md.sh`, which runs only with the
owner's approval.

## Verification

- `scripts/tests/test_outside_agent.sh`, temp `HOME` and a `PATH` of stub agents:
  conf generated when missing; existing conf untouched and diff printed;
  `Not logged in` + exit 0 → `auth`; 401 → `auth`, demoted, still tried last;
  each rate-limit phrase → skipped until reset, `kiro` group skips both kinds,
  monthly reset computed across a year boundary; bare `429` → `error` exit 2;
  unknown error stops; review same-family-only → exit 3; inherited
  `ANTHROPIC_*` does not leak into the `claude` stub; unknown conf name → exit 2.
- Passes under `/bin/bash` 3.2 and bash 5.
- `RUN_INTEGRATION=1` case runs one real `run --purpose review` on this machine.
- `harness-verify.sh` gains a drift check: installed `outside-agent.sh`,
  `lib.sh`, `_store.sh` match the repo.

## Open

- Real usage-limit messages from each candidate have not been observed; phrases
  are the owner's chosen set and will be extended from real output.
- No cheap login signal for `agy` is known; it relies on run-time classification.
