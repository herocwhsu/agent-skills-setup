---
name: infra-ups
description: Configure NUT for APC UPS: 60-second power-loss → graceful shutdown + battery longevity settings. Subcommands: setup, status, battery-health, test-shutdown, remove.
---

# infra/ups

Manage UPS power protection via NUT (Network UPS Tools).

## Subcommands

| Subcommand | What it does |
|---|---|
| `setup` | Install NUT, write /etc/nut config, enable services, apply battery longevity settings |
| `status` | Print UPS state (battery %, load, runtime, sensitivity, install date) |
| `battery-health` | Show longevity metrics and auto-fix any out-of-spec settings |
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
| `lib/install.sh` | Install NUT + write all /etc/nut config files + apply longevity settings |
| `lib/battery-health.sh` | Show and auto-fix battery longevity settings via upsrw |
| `lib/shutdown.sh` | Graceful shutdown sequence (k3s → docker → zfs → sync → poweroff) |
| `lib/status.sh` | Print current UPS status + battery health indicators |

## Battery longevity settings (applied by setup)

| Setting | Default | Applied | Reason |
|---|---|---|---|
| `battery.charge.low` | 10% | **30%** | Prevents deep discharge — main SLA killer |
| `battery.runtime.low` | 120s | **300s** | 5-min margin before shutdown trigger |
| `input.sensitivity` | high | **low** | Fewer unnecessary battery transfers |
| `battery.mfr.date` | factory | **install date** | Tracks battery age for replacement planning |

## Prerequisites

- APC Back-UPS RS 1500G connected via USB
- sudo access
- Ubuntu 22.04+ / Debian 12+
- NUT 2.8+ (uses `nut-driver.target`, not deprecated `nut-driver.service`)
