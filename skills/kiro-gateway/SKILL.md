---
name: kiro-gateway
description: Use when the user wants to initialize, update, rollback, or check the status of the kiro-gateway Docker container. Manages a digest-pinned image with one-step rollback. Subcommands: init, update, rollback, status.
---

# kiro-gateway

Manages the kiro-gateway Docker container — the proxy that lets Claude Code and Kiro IDE authenticate through AWS/Kiro credentials to use Claude models.

## Usage

Ask Claude to:
- "Set up kiro-gateway" → runs `init`
- "Update kiro-gateway" → runs `update`
- "Rollback kiro-gateway" → runs `rollback`
- "Show kiro-gateway status" → runs `status`

Claude will call:
```bash
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh <subcommand>
```

## Subcommands

| Subcommand | What it does |
|---|---|
| `init` | Start the container. Pins digest on first run. Idempotent. |
| `update` | Pull latest, confirm new digest, recreate container. |
| `rollback` | Revert to previous digest. Swaps current ↔ previous in state. |
| `status` | Show container state, current digest, previous digest. |

## State file

`~/.agent-skills-setup/kiro-gateway.state` — two lines:
```
current=ghcr.io/jwadow/kiro-gateway@sha256:<digest>
previous=ghcr.io/jwadow/kiro-gateway@sha256:<old-digest>
```
`previous` is absent until the first `update`.
