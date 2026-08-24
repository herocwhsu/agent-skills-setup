---
name: infra-kiro-gateway
description: Use when the user wants to initialize, update, rollback, or check the status of the kiro-gateway Docker container. Builds a SHA-tagged image locally from a fork checkout, with one-step rollback. Subcommands: init, update, rollback, status, setup-alias, setup-codex, remove-codex.
---

# kiro-gateway

Manages the kiro-gateway Docker container — the proxy that lets Claude Code and Kiro IDE authenticate through AWS/Kiro credentials to use Claude models.

## Usage

Ask Claude to:
- "Set up kiro-gateway" → runs `init`
- "Update kiro-gateway" → runs `update`
- "Rollback kiro-gateway" → runs `rollback`
- "Show kiro-gateway status" → runs `status`
- "Set up claude-kiro alias" → runs `setup-alias`
- "Set up codex-kiro" → runs `setup-codex`
- "Remove codex-kiro" → runs `remove-codex`

Claude will call:
```bash
bash ~/.claude/skills/infra/kiro-gateway/lib/kiro-gateway.sh <subcommand>
```

## Subcommands

| Subcommand | What it does |
|---|---|
| `init` | Resolve the build path (clone the fork, or symlink an existing checkout via `KIRO_GATEWAY_DIR`), run fix-guard, build a SHA-tagged image, start the container. Idempotent. |
| `update` | `git pull --ff-only` the fork checkout, run fix-guard, rebuild, recreate the container if the SHA changed. |
| `rollback` | Revert to the previous SHA-tagged image. Swaps current ↔ previous in state. |
| `status` | Show build path, current image tag, container state, current/previous SHA. |
| `setup-alias` | Add `KIRO_PROXY_KEY` + `claude-kiro` alias to shell rc file. |
| `setup-codex` | Write `~/.codex-kiro/config.toml` (isolated `CODEX_HOME`) + `codex-kiro` alias. Checks for `codex` binary. Idempotent. |
| `remove-codex` | Remove the `codex-kiro` alias and the `~/.codex-kiro` dir. |

## State file

`~/.agent-skills-setup/kiro-gateway.state` — two lines:
```
current=abc1234
previous=def5678
```
Values are short git SHAs of the fork checkout (image tag: `kiro-gateway:<sha>`). `previous` is absent until the first `update`.
