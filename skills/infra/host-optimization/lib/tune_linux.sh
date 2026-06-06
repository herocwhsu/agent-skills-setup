#!/bin/bash
# Host Optimization - Linux
set -euo pipefail

log() { echo "[host-opt] $*"; }

# ── 1. Network & VM sysctl ────────────────────────────────────────────────────
log "Writing sysctl tuning..."
cat <<SYSCTL | sudo tee /etc/sysctl.d/99-performance.conf > /dev/null
# TCP BBR congestion control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Network buffer sizes
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Conservative swap — keep data in RAM, avoid thrashing
vm.swappiness=10
vm.dirty_ratio=20
vm.dirty_background_ratio=10
SYSCTL
sudo sysctl --system > /dev/null
log "  sysctl applied."

# ── 2. CPU Governor: powersave + systemd persistence ─────────────────────────
log "Setting CPU governor..."
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
  if command -v cpupower &>/dev/null; then
    sudo cpupower frequency-set -g powersave > /dev/null
  else
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      echo "powersave" | sudo tee "$gov" > /dev/null
    done
  fi
  log "  CPU governor → powersave (all $(nproc) cores)"

  UNIT=/etc/systemd/system/cpu-powersave.service
  if [ ! -f "$UNIT" ]; then
    sudo tee "$UNIT" > /dev/null <<'EOF'
[Unit]
Description=Set CPU governor to powersave
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g powersave
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable cpu-powersave.service > /dev/null 2>&1
    log "  systemd unit installed: $UNIT (persists across reboots)"
  else
    log "  systemd unit already present: $UNIT"
  fi
else
  log "  cpufreq not available — skipping (may be managed by intel_pstate)"
fi

# ── 3. PCI Power Management ──────────────────────────────────────────────────
log "Enabling PCI runtime power management..."
UDEV_RULE=/etc/udev/rules.d/70-pci-pm.rules
if [ ! -f "$UDEV_RULE" ]; then
  echo 'ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"' \
    | sudo tee "$UDEV_RULE" > /dev/null
  log "  udev rule written: $UDEV_RULE"
else
  log "  udev rule already present: $UDEV_RULE"
fi
sudo bash -c 'for dev in /sys/bus/pci/devices/*/power/control; do echo "auto" > "$dev" 2>/dev/null || true; done'
ON=$(cat /sys/bus/pci/devices/*/power/control 2>/dev/null | grep -c "^on$" || true)
log "  PCI devices remaining forced-on: $ON"

# ── 4. Nouveau GPU fix (Fermi-era CTXSW timeout) ─────────────────────────────
NOUVEAU_CONF=/etc/modprobe.d/nouveau.conf
if lsmod 2>/dev/null | grep -q "^nouveau"; then
  if [ ! -f "$NOUVEAU_CONF" ]; then
    log "Applying nouveau modprobe fix (clock-switch timeout on old GPUs)..."
    printf 'options nouveau config=NvClkMode=0x0\noptions nouveau runpm=0\n' \
      | sudo tee "$NOUVEAU_CONF" > /dev/null
    sudo update-initramfs -u 2>/dev/null | grep -v "^$" || true
    log "  nouveau fix applied — reboot required to activate"
  else
    log "  nouveau modprobe fix already in place."
  fi
else
  log "  nouveau not loaded — GPU fix skipped."
fi

# ── 5. Disable unnecessary services ──────────────────────────────────────────
log "Disabling unnecessary services..."
BLOAT=(kerneloops colord switcheroo-control)
for svc in "${BLOAT[@]}"; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    sudo systemctl disable --now "$svc" 2>/dev/null || true
    log "  disabled: $svc"
  else
    log "  already inactive: $svc"
  fi
done

# ── 6. APT sources validation ─────────────────────────────────────────────────
log "Checking apt sources..."
APT_ERRORS=$(apt-get update --dry-run 2>&1 | grep -c "^E:" || true)
if [ "$APT_ERRORS" -gt 0 ]; then
  log "  WARNING: $APT_ERRORS apt source error(s) — check /etc/apt/sources.list.d/*.list"
  apt-get update --dry-run 2>&1 | grep "^E:" | head -5 | sed 's/^/    /'
else
  log "  apt sources OK"
fi

log ""
log "Linux optimization complete."
log "Note: PCI PM and nouveau fix take full effect after reboot."
