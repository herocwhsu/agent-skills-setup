# UPS Power Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install and configure NUT (Network UPS Tools) so that when the APC Back-UPS RS 1500G loses mains power for ≥ 60 seconds, the host gracefully stops k3s, Docker, ZFS, and remaining services, flushes disk caches, then shuts down safely.

**Architecture:** NUT runs in standalone mode with the `usbhid-ups` driver talking directly to the APC USB HID device. `upsmon` delegates timed events to `upssched`, which starts a 60-second countdown on battery and cancels it if power returns. On expiry `upssched` calls a graceful-shutdown script that drains k3s, stops Docker/containerd, syncs ZFS pools, runs `sync`, then triggers `systemctl poweroff`. A LOWBATT fallback triggers immediate shutdown if the battery drops critically before the timer fires.

**Tech Stack:** NUT 2.8.x (`apt`), `usbhid-ups` driver, `upssched` event timer, bash shutdown script, systemd services (`nut-driver`, `nut-server`, `nut-monitor`).

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `skills/infra/ups/IMPL.md` | Skill entry point Claude reads |
| Create | `skills/infra/ups/README.md` | Human-facing docs |
| Create | `skills/infra/ups/lib/ups.sh` | Subcommand dispatcher |
| Create | `skills/infra/ups/lib/install.sh` | Install NUT + write all config files |
| Create | `skills/infra/ups/lib/shutdown.sh` | Graceful shutdown sequence (called by upssched) |
| Create | `skills/infra/ups/lib/status.sh` | Print UPS state |
| Create | `skills/infra/ups/tests/test_ups.sh` | Test suite (dry-run and live checks) |
| Modify | `skills/infra/SKILL.md` | Add `/infra-ups` row to subcommands table |
| Modify | `registry.txt` | Register the `ups` skill |

NUT config files are written by `install.sh` to `/etc/nut/`; the shutdown script lands at `/usr/local/sbin/ups-graceful-shutdown.sh`.

---

## Task 1: Scaffold skill directory and stub files

**Files:**
- Create: `skills/infra/ups/IMPL.md`
- Create: `skills/infra/ups/README.md`
- Create: `skills/infra/ups/lib/ups.sh`
- Create: `skills/infra/ups/lib/install.sh`
- Create: `skills/infra/ups/lib/shutdown.sh`
- Create: `skills/infra/ups/lib/status.sh`
- Create: `skills/infra/ups/tests/test_ups.sh`

- [ ] **Step 1: Create directory tree**

```bash
mkdir -p skills/infra/ups/lib skills/infra/ups/tests
```

- [ ] **Step 2: Create IMPL.md stub**

```bash
cat > skills/infra/ups/IMPL.md << 'EOF'
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
EOF
```

- [ ] **Step 3: Create executable stubs for lib scripts**

```bash
for f in lib/ups.sh lib/install.sh lib/shutdown.sh lib/status.sh; do
  cat > skills/infra/ups/$f << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "TODO: not yet implemented" >&2
exit 1
EOF
  chmod +x skills/infra/ups/$f
done
```

- [ ] **Step 4: Create test stub**

```bash
cat > skills/infra/ups/tests/test_ups.sh << 'EOF'
#!/usr/bin/env bash
# UPS skill tests — run as: bash tests/test_ups.sh
set -euo pipefail
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; ((PASS++)); }
fail(){ echo "FAIL: $1"; ((FAIL++)); }

# placeholder — real tests added in Task 5
echo "No tests yet"
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
EOF
chmod +x skills/infra/ups/tests/test_ups.sh
```

- [ ] **Step 5: Verify tree**

```bash
find skills/infra/ups -type f | sort
```

Expected:
```
skills/infra/ups/IMPL.md
skills/infra/ups/README.md  (empty for now, filled in Task 6)
skills/infra/ups/lib/install.sh
skills/infra/ups/lib/shutdown.sh
skills/infra/ups/lib/status.sh
skills/infra/ups/lib/ups.sh
skills/infra/ups/tests/test_ups.sh
```

- [ ] **Step 6: Commit**

```bash
git add skills/infra/ups/
git commit -m "feat(ups): scaffold infra/ups skill directory and stubs"
```

---

## Task 2: Write `install.sh` — NUT install and /etc/nut config

**Files:**
- Modify: `skills/infra/ups/lib/install.sh`

This script installs `nut`, writes every `/etc/nut/` config file, and enables the three NUT systemd units. It is idempotent — running it twice is safe.

- [ ] **Step 1: Write install.sh**

```bash
cat > skills/infra/ups/lib/install.sh << 'SCRIPT'
#!/usr/bin/env bash
# Install NUT and configure for APC Back-UPS RS 1500G (USB HID).
# Requires sudo. Idempotent.
set -euo pipefail

UPS_NAME="apc-rs1500g"
NUT_USER="upsmon"
NUT_PASS="upsmon_secret_$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"
NUT_CONF_DIR="/etc/nut"
SHUTDOWN_SCRIPT="/usr/local/sbin/ups-graceful-shutdown.sh"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

log() { echo "[ups-install] $*"; }

# ── 1. Install NUT ──────────────────────────────────────────────────────────
log "Installing nut..."
sudo apt-get install -y nut nut-client

# ── 2. /etc/nut/nut.conf  (mode) ────────────────────────────────────────────
log "Writing nut.conf..."
sudo tee "$NUT_CONF_DIR/nut.conf" > /dev/null << EOF
MODE=standalone
EOF

# ── 3. /etc/nut/ups.conf  (driver) ──────────────────────────────────────────
log "Writing ups.conf..."
sudo tee "$NUT_CONF_DIR/ups.conf" > /dev/null << EOF
[$UPS_NAME]
  driver = usbhid-ups
  port   = auto
  desc   = "APC Back-UPS RS 1500G"
EOF

# ── 4. /etc/nut/upsd.conf  (server listen) ──────────────────────────────────
log "Writing upsd.conf..."
sudo tee "$NUT_CONF_DIR/upsd.conf" > /dev/null << EOF
LISTEN 127.0.0.1 3493
MAXAGE 15
EOF

# ── 5. /etc/nut/upsd.users  (upsmon credentials) ────────────────────────────
# Re-use existing password if already set to keep upsmon.conf in sync.
if sudo grep -q "^password" "$NUT_CONF_DIR/upsd.users" 2>/dev/null; then
  NUT_PASS=$(sudo grep "^password" "$NUT_CONF_DIR/upsd.users" | awk '{print $3}')
  log "Re-using existing upsd.users password."
fi

log "Writing upsd.users..."
sudo tee "$NUT_CONF_DIR/upsd.users" > /dev/null << EOF
[$NUT_USER]
  password = $NUT_PASS
  upsmon master
EOF
sudo chmod 640 "$NUT_CONF_DIR/upsd.users"
sudo chown root:nut "$NUT_CONF_DIR/upsd.users"

# ── 6. /etc/nut/upsmon.conf ──────────────────────────────────────────────────
log "Writing upsmon.conf..."
sudo tee "$NUT_CONF_DIR/upsmon.conf" > /dev/null << EOF
MONITOR ${UPS_NAME}@localhost 1 ${NUT_USER} ${NUT_PASS} master

MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
POWERDOWNFLAG /etc/killpower
FINALDELAY 5

NOTIFYCMD /sbin/upssched
NOTIFYFLAG ONLINE  SYSLOG+EXEC
NOTIFYFLAG ONBATT  SYSLOG+EXEC
NOTIFYFLAG LOWBATT SYSLOG+EXEC+WALL
NOTIFYFLAG FSD     SYSLOG+WALL
NOTIFYFLAG COMMOK  SYSLOG
NOTIFYFLAG COMMBAD SYSLOG+WALL
NOTIFYFLAG SHUTDOWN SYSLOG+WALL
NOTIFYFLAG REPLBATT SYSLOG+WALL
NOTIFYFLAG NOCOMM  SYSLOG+WALL

RBWARNTIME 43200
NOCOMMWARNTIME 300
EOF
sudo chmod 640 "$NUT_CONF_DIR/upsmon.conf"
sudo chown root:nut "$NUT_CONF_DIR/upsmon.conf"

# ── 7. /etc/nut/upssched.conf ────────────────────────────────────────────────
log "Writing upssched.conf..."
sudo tee "$NUT_CONF_DIR/upssched.conf" > /dev/null << EOF
CMDSCRIPT /etc/nut/upssched-cmd
PIPEFN /var/run/nut/upssched.pipe
LOCKFN /var/run/nut/upssched.lock

# Start 60-second countdown when mains power is lost
AT ONBATT * START-TIMER onbatt 60

# Cancel if power returns before timer fires
AT ONLINE * CANCEL-TIMER onbatt online

# Immediate shutdown if battery goes critically low
AT LOWBATT * EXECUTE lowbatt-shutdown
EOF

# ── 8. /etc/nut/upssched-cmd ─────────────────────────────────────────────────
log "Writing upssched-cmd..."
sudo tee "$NUT_CONF_DIR/upssched-cmd" > /dev/null << EOF
#!/usr/bin/env bash
case "\$1" in
  onbatt)
    logger -t ups-scheduler "Power lost for 60s — starting graceful shutdown"
    $SHUTDOWN_SCRIPT "power_lost_60s" &
    ;;
  lowbatt-shutdown)
    logger -t ups-scheduler "Battery critically low — immediate graceful shutdown"
    $SHUTDOWN_SCRIPT "low_battery" &
    ;;
  online)
    logger -t ups-scheduler "Power restored — shutdown cancelled"
    ;;
  *)
    logger -t ups-scheduler "Unknown event: \$1"
    ;;
esac
EOF
sudo chmod +x "$NUT_CONF_DIR/upssched-cmd"

# ── 9. Install the shutdown script ──────────────────────────────────────────
log "Installing shutdown script to $SHUTDOWN_SCRIPT..."
sudo install -m 755 "$SKILL_DIR/lib/shutdown.sh" "$SHUTDOWN_SCRIPT"

# ── 10. Fix /etc/nut directory permissions ───────────────────────────────────
sudo chown -R root:nut "$NUT_CONF_DIR"
sudo chmod 750 "$NUT_CONF_DIR"

# ── 11. Enable and start NUT services ────────────────────────────────────────
log "Enabling NUT services..."
sudo systemctl enable --now nut-driver.service
sudo systemctl enable --now nut-server.service
sudo systemctl enable --now nut-monitor.service

log "Waiting for upsd to start..."
sleep 2

log "Verifying UPS is reachable..."
if upsc ${UPS_NAME}@localhost > /dev/null 2>&1; then
  log "SUCCESS: UPS is online."
  upsc ${UPS_NAME}@localhost | grep -E "battery.charge|battery.runtime|ups.status|input.voltage"
else
  log "WARNING: upsc could not reach UPS yet. Check: sudo systemctl status nut-driver nut-server"
fi
SCRIPT
chmod +x skills/infra/ups/lib/install.sh
```

- [ ] **Step 2: Verify script is syntactically valid**

```bash
bash -n skills/infra/ups/lib/install.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 3: Commit**

```bash
git add skills/infra/ups/lib/install.sh
git commit -m "feat(ups): write NUT install.sh with full /etc/nut config"
```

---

## Task 3: Write `shutdown.sh` — graceful service stop and disk sync

**Files:**
- Modify: `skills/infra/ups/lib/shutdown.sh`

Called by `upssched-cmd` with a reason string. Stops services in dependency order (k3s drains first, then docker, then containerd), syncs ZFS, flushes page cache, then powers off.

- [ ] **Step 1: Write shutdown.sh**

```bash
cat > skills/infra/ups/lib/shutdown.sh << 'SCRIPT'
#!/usr/bin/env bash
# Graceful UPS shutdown.
# Usage: shutdown.sh <reason>
# Called by /etc/nut/upssched-cmd — runs as root via upssched.
set -euo pipefail

REASON="${1:-unknown}"
LOG_TAG="ups-shutdown"
TIMEOUT_K3S=60     # seconds to wait for k3s to drain
TIMEOUT_DOCKER=30  # seconds to wait for docker stop

log()  { logger -t "$LOG_TAG" "$*"; echo "[$LOG_TAG] $*"; }
warn() { logger -t "$LOG_TAG" "WARN: $*"; echo "[$LOG_TAG] WARN: $*" >&2; }

log "=== Graceful shutdown triggered. Reason: $REASON ==="

# ── Prevent double-run ───────────────────────────────────────────────────────
LOCKFILE=/var/run/ups-shutdown.lock
if [[ -f "$LOCKFILE" ]]; then
  log "Shutdown already in progress (lockfile exists). Exiting."
  exit 0
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# ── 1. Stop k3s (Kubernetes) ─────────────────────────────────────────────────
if systemctl is-active --quiet k3s.service 2>/dev/null; then
  log "Stopping k3s (timeout ${TIMEOUT_K3S}s)..."
  systemctl stop k3s.service --timeout=${TIMEOUT_K3S} || warn "k3s stop timed out"
else
  log "k3s not running, skipping."
fi

# ── 2. Stop Docker containers then Docker daemon ─────────────────────────────
if systemctl is-active --quiet docker.service 2>/dev/null; then
  log "Stopping all Docker containers (timeout ${TIMEOUT_DOCKER}s each)..."
  if command -v docker &>/dev/null; then
    docker stop --time=$TIMEOUT_DOCKER $(docker ps -q) 2>/dev/null || true
  fi
  log "Stopping Docker daemon..."
  systemctl stop docker.service docker.socket 2>/dev/null || warn "docker stop failed"
else
  log "Docker not running, skipping."
fi

# ── 3. Stop containerd ───────────────────────────────────────────────────────
if systemctl is-active --quiet containerd.service 2>/dev/null; then
  log "Stopping containerd..."
  systemctl stop containerd.service || warn "containerd stop failed"
else
  log "containerd not running, skipping."
fi

# ── 4. Sync ZFS pools ────────────────────────────────────────────────────────
if command -v zpool &>/dev/null; then
  log "Syncing ZFS pools..."
  zpool sync 2>/dev/null || warn "zpool sync failed (pool may not be imported)"
  log "ZFS sync complete."
else
  log "ZFS not found, skipping."
fi

# ── 5. Flush kernel page cache and dentries ──────────────────────────────────
log "Flushing disk caches (sync + drop_caches)..."
sync
echo 3 > /proc/sys/vm/drop_caches || true
sync

# ── 6. Power off ─────────────────────────────────────────────────────────────
log "=== All services stopped. Issuing shutdown. ==="
systemctl poweroff --no-wall
SCRIPT
chmod +x skills/infra/ups/lib/shutdown.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n skills/infra/ups/lib/shutdown.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 3: Commit**

```bash
git add skills/infra/ups/lib/shutdown.sh
git commit -m "feat(ups): write graceful shutdown script (k3s→docker→zfs→sync→poweroff)"
```

---

## Task 4: Write `status.sh` and `ups.sh` dispatcher

**Files:**
- Modify: `skills/infra/ups/lib/status.sh`
- Modify: `skills/infra/ups/lib/ups.sh`

- [ ] **Step 1: Write status.sh**

```bash
cat > skills/infra/ups/lib/status.sh << 'SCRIPT'
#!/usr/bin/env bash
# Print UPS status. Requires NUT to be installed and running.
set -euo pipefail
UPS_NAME="apc-rs1500g"

if ! command -v upsc &>/dev/null; then
  echo "ERROR: NUT not installed. Run: /infra-ups setup" >&2
  exit 1
fi

if ! upsc "${UPS_NAME}@localhost" > /dev/null 2>&1; then
  echo "ERROR: Cannot reach ${UPS_NAME}@localhost. Is nut-server running?" >&2
  echo "  sudo systemctl status nut-driver nut-server nut-monitor" >&2
  exit 1
fi

echo "=== UPS Status: $UPS_NAME ==="
upsc "${UPS_NAME}@localhost" 2>/dev/null | grep -E \
  "battery\.charge|battery\.charge\.low|battery\.runtime|battery\.voltage|"\
  "input\.voltage|output\.voltage|ups\.load|ups\.status|ups\.model|"\
  "driver\.name|ups\.mfr" | sort
echo ""
echo "NUT services:"
for svc in nut-driver nut-server nut-monitor; do
  STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
  printf "  %-20s %s\n" "$svc" "$STATUS"
done
SCRIPT
chmod +x skills/infra/ups/lib/status.sh
```

- [ ] **Step 2: Write ups.sh dispatcher**

```bash
cat > skills/infra/ups/lib/ups.sh << 'SCRIPT'
#!/usr/bin/env bash
# /infra-ups dispatcher
set -euo pipefail
SKILL_LIB="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: ups.sh <subcommand>"
  echo "  setup          Install NUT and configure for APC Back-UPS RS 1500G"
  echo "  status         Show UPS battery, load, runtime, on-battery state"
  echo "  test-shutdown  Dry-run the shutdown script (no actual poweroff)"
  echo "  remove         Stop NUT services, remove /etc/nut config, uninstall"
}

case "${1:-}" in
  setup)
    exec bash "$SKILL_LIB/install.sh"
    ;;
  status)
    exec bash "$SKILL_LIB/status.sh"
    ;;
  test-shutdown)
    echo "[test-shutdown] Dry-run: would execute ups-graceful-shutdown.sh with reason=test"
    echo ""
    echo "Shutdown sequence (DRY RUN — no services stopped, no poweroff):"
    echo "  1. Stop k3s.service"
    echo "  2. Stop all Docker containers"
    echo "  3. Stop docker.service + docker.socket"
    echo "  4. Stop containerd.service"
    echo "  5. zpool sync"
    echo "  6. sync && echo 3 > /proc/sys/vm/drop_caches"
    echo "  7. systemctl poweroff"
    echo ""
    echo "To run a real test (with actual shutdown), use:"
    echo "  sudo /usr/local/sbin/ups-graceful-shutdown.sh test_manual"
    ;;
  remove)
    echo "Removing NUT configuration and services..."
    sudo systemctl disable --now nut-monitor nut-server nut-driver 2>/dev/null || true
    sudo apt-get remove -y nut nut-client 2>/dev/null || true
    sudo rm -rf /etc/nut /usr/local/sbin/ups-graceful-shutdown.sh
    echo "Done. NUT removed."
    ;;
  help|--help|-h|"")
    usage
    ;;
  *)
    echo "Unknown subcommand: $1" >&2
    usage >&2
    exit 1
    ;;
esac
SCRIPT
chmod +x skills/infra/ups/lib/ups.sh
```

- [ ] **Step 3: Verify both scripts**

```bash
bash -n skills/infra/ups/lib/status.sh && echo "status.sh OK"
bash -n skills/infra/ups/lib/ups.sh    && echo "ups.sh OK"
```

Expected:
```
status.sh OK
ups.sh OK
```

- [ ] **Step 4: Commit**

```bash
git add skills/infra/ups/lib/status.sh skills/infra/ups/lib/ups.sh
git commit -m "feat(ups): write status.sh and ups.sh subcommand dispatcher"
```

---

## Task 5: Write tests

**Files:**
- Modify: `skills/infra/ups/tests/test_ups.sh`

Tests verify script structure and safety properties without requiring NUT to be installed or a UPS to be connected.

- [ ] **Step 1: Write test suite**

```bash
cat > skills/infra/ups/tests/test_ups.sh << 'SCRIPT'
#!/usr/bin/env bash
# UPS skill unit tests — no UPS or NUT installation required.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

ok()   { echo "PASS: $1"; ((PASS++)); }
fail() { echo "FAIL: $1"; ((FAIL++)); }

# ── Syntax checks ─────────────────────────────────────────────────────────────
for f in lib/ups.sh lib/install.sh lib/shutdown.sh lib/status.sh; do
  if bash -n "$SKILL_DIR/$f" 2>/dev/null; then
    ok "syntax: $f"
  else
    fail "syntax: $f"
  fi
done

# ── Executable bits ───────────────────────────────────────────────────────────
for f in lib/ups.sh lib/install.sh lib/shutdown.sh lib/status.sh; do
  if [[ -x "$SKILL_DIR/$f" ]]; then
    ok "executable: $f"
  else
    fail "executable: $f — missing +x"
  fi
done

# ── ups.sh: unknown subcommand exits non-zero ─────────────────────────────────
if ! bash "$SKILL_DIR/lib/ups.sh" __bogus__ 2>/dev/null; then
  ok "ups.sh: unknown subcommand exits non-zero"
else
  fail "ups.sh: unknown subcommand should exit non-zero"
fi

# ── ups.sh: test-shutdown subcommand works without NUT installed ─────────────
if bash "$SKILL_DIR/lib/ups.sh" test-shutdown 2>/dev/null | grep -q "DRY RUN"; then
  ok "ups.sh test-shutdown: dry-run output contains 'DRY RUN'"
else
  fail "ups.sh test-shutdown: expected 'DRY RUN' in output"
fi

# ── shutdown.sh: double-run protection (lockfile logic) ──────────────────────
# Create a fake lockfile and verify the script exits 0 without running
LOCKFILE=/var/run/ups-shutdown.lock
if [[ -w /var/run ]] || sudo touch "$LOCKFILE" 2>/dev/null; then
  sudo touch "$LOCKFILE"
  if sudo bash "$SKILL_DIR/lib/shutdown.sh" test 2>&1 | grep -q "already in progress"; then
    ok "shutdown.sh: double-run protection works"
  else
    fail "shutdown.sh: double-run protection not working"
  fi
  sudo rm -f "$LOCKFILE"
else
  echo "SKIP: double-run test (no write access to /var/run)"
fi

# ── install.sh: key config strings are present ───────────────────────────────
for pattern in "usbhid-ups" "upssched" "START-TIMER onbatt 60" "CANCEL-TIMER onbatt" "LOWBATT.*EXECUTE"; do
  if grep -qP "$pattern" "$SKILL_DIR/lib/install.sh"; then
    ok "install.sh contains: $pattern"
  else
    fail "install.sh missing: $pattern"
  fi
done

# ── shutdown.sh: all four stop stages present ────────────────────────────────
for pattern in "k3s.service" "docker ps -q" "containerd.service" "zpool sync" "drop_caches" "systemctl poweroff"; do
  if grep -q "$pattern" "$SKILL_DIR/lib/shutdown.sh"; then
    ok "shutdown.sh contains: $pattern"
  else
    fail "shutdown.sh missing: $pattern"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
SCRIPT
chmod +x skills/infra/ups/tests/test_ups.sh
```

- [ ] **Step 2: Run tests**

```bash
bash skills/infra/ups/tests/test_ups.sh
```

Expected: all tests PASS, exit 0.

- [ ] **Step 3: Commit**

```bash
git add skills/infra/ups/tests/test_ups.sh
git commit -m "test(ups): add unit tests for syntax, structure, and shutdown safety"
```

---

## Task 6: Write README.md and register in SKILL.md + registry.txt

**Files:**
- Modify: `skills/infra/ups/README.md`
- Modify: `skills/infra/SKILL.md`
- Modify: `registry.txt`

- [ ] **Step 1: Write README.md**

```bash
cat > skills/infra/ups/README.md << 'EOF'
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
EOF
```

- [ ] **Step 2: Add /infra-ups row to skills/infra/SKILL.md**

Find the subcommands table and add a new row. The table currently has rows for `kiro-gateway` and `host-optimization`. Add after the last row:

```
| `/infra-ups <subcommand>` | Manage UPS power protection via NUT. Sub-subcommands: `setup`, `status`, `test-shutdown`, `remove`. Triggers graceful shutdown after 60 s on battery. | `ups/IMPL.md` |
```

Edit `skills/infra/SKILL.md` to insert this row into the table.

- [ ] **Step 3: Add to registry.txt**

```bash
echo "local  infra-ups" >> registry.txt
# Keep registry sorted by skill name
sort -k2 registry.txt -o registry.txt
```

- [ ] **Step 4: Verify registry entry**

```bash
grep "infra-ups" registry.txt
```

Expected: `local  infra-ups`

- [ ] **Step 5: Run full test suite one final time**

```bash
bash skills/infra/ups/tests/test_ups.sh
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add skills/infra/ups/README.md skills/infra/SKILL.md registry.txt
git commit -m "docs(ups): README, register in infra SKILL.md and registry.txt"
```

---

## Self-Review

### Spec coverage

| Requirement | Covered by |
|---|---|
| Detect APC Back-UPS RS 1500G | Task 2 — `usbhid-ups` driver, `port=auto` |
| 60-second delay before action | Task 2 — `upssched.conf` `START-TIMER onbatt 60` |
| Cancel if power restores | Task 2 — `CANCEL-TIMER onbatt online` |
| Stop services gracefully | Task 3 — k3s → docker → containerd |
| Flush disk / ZFS cache | Task 3 — `zpool sync`, `sync`, `drop_caches` |
| Shutdown | Task 3 — `systemctl poweroff` |
| Low-battery fallback | Task 2 — `AT LOWBATT * EXECUTE lowbatt-shutdown` |
| Status command | Task 4 |
| Test without actual poweroff | Task 4 — `test-shutdown` dry-run |
| Skill registered + documented | Task 6 |

### Potential gaps checked

- **Double-run protection**: lockfile in `shutdown.sh` prevents two simultaneous shutdowns ✓
- **k3s drain**: `systemctl stop k3s` waits for graceful pod termination up to 60 s ✓
- **Docker timeout**: containers get 30 s to stop before daemon exits ✓
- **ZFS not installed**: guarded with `command -v zpool` ✓
- **NUT not installed**: `status.sh` gives clear error with fix command ✓
- **Password idempotency**: `install.sh` reuses existing password on re-run ✓
