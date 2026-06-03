---
title: kiro-gateway skill
date: 2026-06-03
status: approved
---

# kiro-gateway skill

Skill for managing the kiro-gateway Docker container — the proxy that lets Claude Code and Kiro IDE use free Claude models via AWS/Kiro credentials.

## Problem

The kiro-gateway container is started manually with a `docker run` command that must be reconstructed from memory if the container is removed. There is no pinned version, no rollback path, and no standard way to hand setup off to an AI agent.

## Goals

- One-command init, update, rollback, and status via a skill
- Digest-pinned image so updates are explicit and reversible
- Platform-aware data dir detection (macOS vs Linux)
- State persisted in `~/.agent-skills-setup/kiro-gateway.state`
- Fits the existing `agent-skills-setup` install pattern (local skill, no hook)

## Non-Goals

- Building a custom Docker image (upstream `ghcr.io/jwadow/kiro-gateway` is sufficient)
- Changing the container's internal port (8000 is hardcoded by the app)
- Windows support (Docker Desktop on Windows is out of scope for v1)

## Image Source

| Field | Value |
|---|---|
| Registry | `ghcr.io/jwadow/kiro-gateway` |
| Source repo | https://github.com/jwadow/kiro-gateway |
| License | AGPL-3.0 |
| Current digest | `sha256:480c2371d9a010d5092fb2ac351ced0b6162e9b116a8de14e98bb0f899b1b1a8` |

The image is maintained upstream. We pin by digest for reproducibility; we do not fork or build locally.

## Container Configuration

```
name:          kiro-gateway
image:         ghcr.io/jwadow/kiro-gateway@sha256:<pinned-digest>
port binding:  127.0.0.1:7788 → container:8000
volume:        <kiro-data-dir> → /home/ubuntu/.local/share/kiro-cli  (rw)
restart:       unless-stopped
cmd:           python main.py
```

Platform kiro data dirs:

| OS | Path |
|---|---|
| macOS | `$HOME/Library/Application Support/kiro-cli` |
| Linux | `$HOME/.local/share/kiro-cli` |

Port `7788` was chosen by the original operator and is kept as-is. The container is bound to `127.0.0.1` only — not reachable from the network.

## State File

`~/.agent-skills-setup/kiro-gateway.state` — plain key=value, two lines max:

```
current=ghcr.io/jwadow/kiro-gateway@sha256:<digest>
previous=ghcr.io/jwadow/kiro-gateway@sha256:<old-digest>
```

`previous` is absent until the first `update` runs. Both keys are full image references including digest, making them directly usable in `docker run`.

## Subcommands

### `init`

1. Check `docker` is available; exit 1 with hint if not
2. Detect platform → resolve kiro data dir; exit 1 if dir does not exist
3. If state file exists → use `current` digest as image ref
4. If no state file → pull `:latest`, resolve digest via `docker inspect`, write `current` to state file
5. If container `kiro-gateway` is already running → print status, exit 0
6. If container exists but stopped → `docker start kiro-gateway`
7. Otherwise → `docker run` with pinned image ref and full config

### `update`

1. Pull `:latest`, resolve new digest
2. Compare to `current` in state file
3. If unchanged → "already up to date", exit 0
4. Print old digest → new digest, ask for confirmation
5. On confirm: write `current` → `previous`, write new digest → `current` in state file
6. `docker stop kiro-gateway && docker rm kiro-gateway`
7. Re-run `init` path (uses new `current` from state file)

### `rollback`

1. Read `previous` from state file; exit 1 if absent ("no previous version recorded")
2. `docker stop kiro-gateway && docker rm kiro-gateway`
3. Start container using `previous` digest
4. Swap `current` ↔ `previous` in state file

### `status`

Print:
- Container running state
- Current image digest
- Previous image digest (if any)
- Host port binding

## File Layout

```
skills/kiro-gateway/
  SKILL.md
  README.md
  lib/
    kiro-gateway.sh
```

`registry.txt` gains one line:
```
local  kiro-gateway
```

No `hook.json` — this skill is invoked on demand, not wired as a hook.

## Install

```bash
bash scripts/install.sh          # picks up kiro-gateway from registry.txt
```

No extra flags needed. The skill is available in `~/.claude/skills/kiro-gateway/` (and `~/.kiro/skills/` if kiro is selected) as a symlink into this repo.

## Error Handling

- `docker` not found → print install hint, exit 1
- kiro data dir missing → print path that was checked, suggest running Kiro once to create it, exit 1
- `docker pull` fails → leave state file unchanged, exit 1
- `previous` absent on rollback → explain, exit 1
- All failures are loud (exit 1 + message) — no silent fallbacks
