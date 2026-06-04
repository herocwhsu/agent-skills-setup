# infra/ups

Configures NUT (Network UPS Tools) for **APC Back-UPS RS 1500G** (USB HID).
When mains power is lost for ≥ 60 seconds, the host stops k3s, Docker,
containerd, syncs ZFS pools, flushes page cache, and shuts down cleanly.
If the battery drops critically before the timer fires, shutdown triggers
immediately.

## Quick start

```bash
# Install and configure NUT
/infra-ups setup

# Check UPS state
/infra-ups status

# Dry-run the shutdown sequence (no actual poweroff)
/infra-ups test-shutdown

# Remove NUT and all config
/infra-ups remove
```

## How it works

```
mains fails
    └─► upsmon detects ONBATT event
            └─► upssched starts 60-second timer
                    ├─ mains restores ──► CANCEL-TIMER (no shutdown)
                    └─ 60 s elapsed  ──► upssched-cmd calls shutdown.sh
                                               ├─ stop k3s
                                               ├─ stop docker containers
                                               ├─ stop containerd
                                               ├─ zpool sync
                                               ├─ sync + drop_caches
                                               └─ systemctl poweroff

battery critically low (any time) ──► immediate shutdown via LOWBATT
```

## Config files written by setup

| File | Purpose |
|---|---|
| `/etc/nut/nut.conf` | mode=standalone |
| `/etc/nut/ups.conf` | usbhid-ups driver, port=auto |
| `/etc/nut/upsd.conf` | listen 127.0.0.1:3493 |
| `/etc/nut/upsd.users` | upsmon credentials |
| `/etc/nut/upsmon.conf` | monitor config, notifycmd=upssched |
| `/etc/nut/upssched.conf` | 60-second ONBATT timer + LOWBATT execute |
| `/etc/nut/upssched-cmd` | event handler script |
| `/usr/local/sbin/ups-graceful-shutdown.sh` | service-stop + disk-sync + poweroff |

## Logs

```bash
journalctl -t ups-shutdown -f      # shutdown script events
journalctl -t ups-scheduler -f     # upssched timer events
journalctl -u nut-monitor -f       # upsmon state changes
```
