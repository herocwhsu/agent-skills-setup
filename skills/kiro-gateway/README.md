# kiro-gateway

Manages the kiro-gateway Docker container with digest pinning and rollback.

## Requirements

- Docker installed and running
- Kiro CLI run at least once (creates the data dir the container mounts)

## Install

```bash
bash scripts/install.sh
```

Adds `~/.claude/skills/kiro-gateway/` (and `~/.kiro/skills/kiro-gateway/` if kiro is selected) as a symlink into this repo.

## Usage

Tell your AI agent: "set up kiro-gateway" / "update kiro-gateway" / "rollback kiro-gateway" / "kiro-gateway status".

Or run directly:

```bash
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh init
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh update
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh rollback
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh status
```

## Container details

| Setting | Value |
|---|---|
| Image | `ghcr.io/jwadow/kiro-gateway` (digest-pinned) |
| Host port | `127.0.0.1:7788` |
| Container port | `8000` |
| Volume | `<kiro-data-dir> → /home/ubuntu/.local/share/kiro-cli` |
| Restart | `unless-stopped` |

Data dir by platform:
- macOS: `$HOME/Library/Application Support/kiro-cli`
- Linux: `$HOME/.local/share/kiro-cli`

## State file

`~/.agent-skills-setup/kiro-gateway.state`

Tracks current and previous digests for rollback. Never delete this file manually — use `rollback` instead.

## Troubleshooting

**"kiro data dir not found"** — Run Kiro IDE or CLI once to create it, then retry `init`.

**"docker: command not found"** — Install Docker Desktop (macOS) or `docker-ce` (Linux).

**"no previous version recorded"** — `rollback` requires at least one prior `update`. There is no version before the first pinned digest.
