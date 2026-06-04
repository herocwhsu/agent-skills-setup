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
sudo tee "$NUT_CONF_DIR/upssched-cmd" > /dev/null << 'EOF'
#!/usr/bin/env bash
SHUTDOWN_SCRIPT="/usr/local/sbin/ups-graceful-shutdown.sh"
case "$1" in
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
    logger -t ups-scheduler "Unknown event: $1"
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
