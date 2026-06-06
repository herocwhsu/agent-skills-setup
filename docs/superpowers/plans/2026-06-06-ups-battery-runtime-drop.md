# UPS Battery Runtime Drop Investigation & Fix

**Date:** 2026-06-06
**Hardware:** APC Back-UPS RS 1500G (`apc-rs1500g`)
**Symptom:** New battery installed ~3 days ago. Initial runtime estimate ~250 min → dropped to ~65 min.

---

## Investigation Summary

### Findings

| Field | Value | Problem |
|---|---|---|
| `battery.runtime` | 3921 s (65 min) | Too low for new battery at 9% load |
| `battery.date` | 2001/09/25 | **Not updated after battery replacement** |
| `battery.mfr.date` | 2026/06/05 | Correct (new battery manufacture date) |
| `ups.load` | 9% (≈78W) | Very low — runtime should be ~142 min |
| `battery.voltage` | 26.9V (nominal 24V) | Healthy |
| `battery.charge` | 100% | Fully charged |

### Root Cause

Two compounding issues:

**1. `battery.date` was never updated (primary cause)**
The APC RS1500G stores a "battery replacement date" in its EEPROM. When a battery is replaced,
this must be updated manually. It currently reads `2001/09/25` — the UPS firmware believes the
battery is 25 years old and applies heavy age-based derating to its runtime estimate.
This field is not writable via NUT's `upsrw`; it requires `apctest` (from `apcupsd` package).

**2. Automatic self-test revised the estimate after ~3 days (secondary cause)**
APC runs a self-test automatically after the first power restore event. It replaced the
initial optimistic factory-spec estimate (~250 min) with a measured value — but that
measured value is heavily penalised by the wrong battery date.

### Expected vs Actual

```
Load:             78W (9% of 865W nominal)
Battery:          24V 9Ah SLA = 216 Wh theoretical
Usable (85% eff): ~184 Wh
Expected runtime: ~142 min
Actual runtime:   ~65 min  ← ~46% of expected → age derating is dominant factor
```

---

## Fix Plan

### Step 1 — Update `battery.date` in UPS EEPROM

`battery.date` is not writable via NUT. Use `apctest` from the `apcupsd` package.
NUT must be stopped first to release the USB device.

```bash
# Stop NUT
sudo systemctl stop nut-monitor nut-server nut-driver.target

# Install apcupsd temporarily (do NOT enable its service)
sudo apt-get install -y apcupsd

# Run apctest interactively — choose option 4 (Set UPS date/time)
# then sub-option to set battery replacement date to today
sudo apctest

# Remove apcupsd and restart NUT
sudo apt-get remove -y apcupsd
sudo systemctl start nut-driver.target nut-server nut-monitor

# Verify date updated
upsc apc-rs1500g | grep battery.date
```

> **Note:** `apctest` is interactive (menu-driven). The battery date option is under
> "UPS Capabilities" → "Battery date". Set it to today's date (2026-06-06).

### Step 2 — Run a deep calibration test

Calibration discharges the battery to ~25% then recharges. This:
- Gives the UPS accurate capacity data for runtime estimation
- Conditions the new SLA battery (new SLAs need 2-3 cycles to reach full capacity)

**Schedule this during a quiet window** — the machine will run on battery for ~30-60 min.
Ensure k3s/Docker workloads are minimal or paused.

```bash
# Trigger deep test (NUT must be running)
upscmd -u upsmon -p <password> apc-rs1500g test.battery.start.deep

# Monitor progress
watch -n5 "upsc apc-rs1500g | grep -E 'battery.charge|battery.runtime|ups.status|ups.test'"
```

The UPS will show `OB` (on battery) during discharge. Runtime estimate updates after
recharge completes (~4-6 hours total including recharge).

### Step 3 — Verify runtime after calibration

```bash
upsc apc-rs1500g | grep -E "battery.date|battery.runtime|battery.charge|ups.load"
```

Expected after fix: runtime ≥ 120 min at current 9% load.
If still below 100 min, check the physical battery Ah rating — a 7Ah replacement
instead of 9Ah would explain ~22% shortfall.

### Step 4 — Document battery.date update in the ups skill

Add a `battery-replace` subcommand to `infra/ups` that walks through the full
replacement procedure: update `battery.date` via apctest, run calibration, verify.
This prevents the same trap on next replacement.

---

## Tasks

- [ ] Stop NUT, install apctest, update `battery.date` to 2026-06-06, remove apcupsd, restart NUT
- [ ] Schedule and run `test.battery.start.deep` during quiet window
- [ ] Monitor runtime estimate after full recharge — verify ≥ 120 min
- [ ] Check physical battery label if runtime still low after calibration
- [ ] Add `battery-replace` subcommand to `infra/ups` skill
