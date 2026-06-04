---
name: infra-ups
description: Configure NUT for APC UPS: 60-second power-loss → graceful shutdown. Subcommands: setup, status, test-shutdown, remove.
---

# infra/ups

Manage UPS power protection via NUT (Network UPS Tools).

## Subcommands

| Subcommand | What it does |
|---|---|
| `setup` | Install NUT, write /etc/nut config, enable services |
| `status` | Print UPS state (battery %, load, runtime, on-battery flag) |
| `test-shutdown` | Dry-run the shutdown script (no actual poweroff) |
| `remove` | Stop NUT services, remove /etc/nut config, uninstall package |

## Invocation

The agent runs:

```bash
bash ~/.claude/skills/infra/ups/lib/ups.sh <subcommand>
```

## Implementation files

| File | Purpose |
|---|---|
| `lib/ups.sh` | Subcommand dispatcher |
| `lib/install.sh` | Install NUT + write all /etc/nut config files |
| `lib/shutdown.sh` | Graceful shutdown sequence (k3s → docker → zfs → sync → poweroff) |
| `lib/status.sh` | Print current UPS status via upsc |

## Prerequisites

- APC Back-UPS RS 1500G connected via USB
- sudo access
- Ubuntu 22.04+ / Debian 12+
