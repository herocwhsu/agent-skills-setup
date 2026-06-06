---
name: host-optimization
description: Linux/macOS host performance and power tuning. Investigates governor, PCI PM, GPU errors, services, apt health, thermals. Applies fixes with --apply. Subcommands: --check (default), --apply, --revert.
---

# Host Optimization

Investigate and apply host-level performance and power tuning.

## Usage

```bash
python3 lib/main.py           # same as --check
python3 lib/main.py --check   # inspect host health, no changes
python3 lib/main.py --apply   # apply all optimizations
python3 lib/main.py --revert  # restore previous sysctl config
```

## What --check inspects

| Area | What it checks |
|---|---|
| CPU governor | Is `powersave` set and persisted via systemd unit? |
| PCI power management | Are devices in `auto`? Is udev rule present? |
| CPU temperature | Flags elevated idle temps (warn >60°C, fail >75°C) |
| GPU / nouveau | CTXSW timeout errors, modprobe fix present, firmware status |
| Services | `kerneloops`, `colord`, `switcheroo-control` running unnecessarily |
| APT health | Source list errors, pending security upgrades |
| Memory | Swap in use, available RAM, swappiness setting |

## What --apply does (Linux)

| Step | Action |
|---|---|
| sysctl | TCP BBR, buffer sizes, swappiness=10, dirty_ratio tuning |
| CPU governor | Set `powersave` on all cores; install `/etc/systemd/system/cpu-powersave.service` for reboot persistence |
| PCI power management | Write `/etc/udev/rules.d/70-pci-pm.rules`, apply immediately |
| Nouveau GPU fix | Detect Fermi-era card, write `/etc/modprobe.d/nouveau.conf`, rebuild initramfs |
| Service cleanup | Disable `kerneloops`, `colord`, `switcheroo-control` |
| APT validation | Report any broken source files |

## Implementation files

| File | Purpose |
|---|---|
| `lib/main.py` | Orchestrator — parses flags, calls check or tune script |
| `lib/detect.py` | Hardware profile: CPU, RAM, GPU vendor/driver/generation, temps |
| `lib/check_linux.sh` | Read-only investigation — outputs PASS/WARN/FAIL per area |
| `lib/tune_linux.sh` | Apply all Linux optimizations |
| `lib/tune_macos.sh` | Apply macOS UI/memory optimizations |
| `lib/backup.py` | Backup/restore `/etc/sysctl.d/99-performance.conf` |

## Reboot requirement

PCI power management and nouveau modprobe fix take full effect after reboot.
The `--check` output will note when a pending reboot is needed.
