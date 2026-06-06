#!/usr/bin/env bash
# Investigate host health — no changes made.
# Outputs PASS/WARN/FAIL per area. Exit 0 if clean, 1 if any WARN/FAIL.
set -euo pipefail

ISSUES=0
warn() { echo "  [WARN] $*"; ((ISSUES++)) || true; }
pass() { echo "  [PASS] $*"; }
fail() { echo "  [FAIL] $*"; ((ISSUES++)) || true; }
section() { echo ""; echo "--- $* ---"; }

# ── Header ────────────────────────────────────────────────────────────────────
HOSTNAME=$(hostname)
CPU=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CORES=$(nproc)
RAM=$(free -h | awk '/^Mem:/{print $2}')
DISTRO=$(lsb_release -d 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
KERNEL=$(uname -r)
LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)

echo "=== Host Check: $HOSTNAME ==="
echo "  CPU:    $CPU ($CORES cores)"
echo "  RAM:    $RAM | Load: $LOAD"
echo "  OS:     $DISTRO | Kernel: $KERNEL"

# ── CPU Governor ──────────────────────────────────────────────────────────────
section "CPU & Power"
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
  GOVS=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort | uniq -c | xargs)
  UNIT_OK=false
  systemctl is-enabled cpu-powersave.service &>/dev/null && UNIT_OK=true
  if echo "$GOVS" | grep -qE "powersave"; then
    $UNIT_OK && pass "CPU governor: $GOVS (persistent)" \
              || warn "CPU governor: $GOVS — not persistent (run --apply to install systemd unit)"
  else
    warn "CPU governor: $GOVS — recommend powersave (run --apply)"
  fi
else
  warn "cpufreq not available — governor check skipped"
fi

# ── PCI Power Management ──────────────────────────────────────────────────────
TOTAL=$(cat /sys/bus/pci/devices/*/power/control 2>/dev/null | wc -l)
ON=$(cat /sys/bus/pci/devices/*/power/control 2>/dev/null | grep -c "^on$" || true)
AUTO=$(cat /sys/bus/pci/devices/*/power/control 2>/dev/null | grep -c "^auto$" || true)
if [ "$ON" -eq 0 ]; then
  pass "PCI power management: $AUTO/$TOTAL devices in auto"
elif [ -f /etc/udev/rules.d/70-pci-pm.rules ]; then
  warn "PCI power management: $ON/$TOTAL devices still forced on (udev rule present — reboot to fully apply)"
else
  warn "PCI power management: $ON/$TOTAL devices forced on — missing /etc/udev/rules.d/70-pci-pm.rules"
fi

# ── CPU Temperature ───────────────────────────────────────────────────────────
if command -v sensors &>/dev/null; then
  MAX_TEMP=$(sensors 2>/dev/null | grep -oP 'Core \d+:\s+\+\K[\d.]+' | sort -n | tail -1)
  if [ -n "$MAX_TEMP" ]; then
    INT_TEMP=${MAX_TEMP%.*}
    if [ "$INT_TEMP" -lt 60 ]; then
      pass "CPU temp: ${MAX_TEMP}°C"
    elif [ "$INT_TEMP" -lt 75 ]; then
      warn "CPU temp: ${MAX_TEMP}°C — elevated at idle, consider reapplying thermal paste"
    else
      fail "CPU temp: ${MAX_TEMP}°C — critical, check cooling immediately"
    fi
  fi
fi

# ── GPU / Nouveau ─────────────────────────────────────────────────────────────
section "GPU"
LSPCI_OUT=$(lspci 2>/dev/null || true)
if echo "$LSPCI_OUT" | grep -qi "nvidia"; then
  GPU=$(echo "$LSPCI_OUT" | grep -i "vga\|3d\|display" | head -1 | sed 's/.*: //')
  DRIVER=$(lsmod 2>/dev/null | grep -oE "^(nouveau|nvidia)" | head -1 || echo "unknown")
  echo "  GPU:    $GPU (driver: $DRIVER)"

  if [ "$DRIVER" = "nouveau" ]; then
    CTXSW=$(journalctl -k --no-pager -S "today" 2>/dev/null | grep -c "SCHED_ERROR" || true)
    MSVLD=$(journalctl -k --no-pager -S "today" 2>/dev/null | grep -c "msvld.*unable" || true)

    if [ "$CTXSW" -gt 0 ]; then
      warn "Nouveau CTXSW errors today: $CTXSW — apply: /infra host-optimization --apply"
    else
      pass "Nouveau: no CTXSW timeout errors today"
    fi

    if [ "$MSVLD" -gt 0 ]; then
      warn "Nouveau msvld firmware missing (hardware video decode unavailable — non-critical)"
    fi

    if grep -q "NvClkMode" /etc/modprobe.d/nouveau.conf 2>/dev/null; then
      pass "Nouveau modprobe fix in place (NvClkMode, runpm=0)"
    else
      warn "Nouveau modprobe fix not applied — GPU clock switching may cause errors"
    fi
  fi
else
  pass "No NVIDIA GPU detected"
fi

# ── Unnecessary Services ──────────────────────────────────────────────────────
section "Services"
SERVER_BLOAT=(kerneloops colord switcheroo-control)
for svc in "${SERVER_BLOAT[@]}"; do
  STATE=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
  if [ "$STATE" = "active" ]; then
    warn "$svc: running — unnecessary on server, disable with: sudo systemctl disable --now $svc"
  else
    pass "$svc: not running"
  fi
done

if systemctl is-active --quiet snapd 2>/dev/null; then
  SNAP_COUNT=$(snap list 2>/dev/null | tail -n +2 | wc -l || echo "?")
  warn "snapd: running ($SNAP_COUNT snaps installed) — disable if not needed"
fi

# ── APT Sources Health (no sudo needed) ──────────────────────────────────────
section "APT Health"
BAD_SOURCES=()
for f in /etc/apt/sources.list.d/*.list; do
  [ -f "$f" ] || continue
  # A valid .list file has only blank lines, comments, deb/deb-src lines
  INVALID=$(grep -vE '^\s*(#|$|deb(-src)?\s)' "$f" 2>/dev/null | wc -l || true)
  [ "$INVALID" -gt 0 ] && BAD_SOURCES+=("$(basename "$f"): $INVALID invalid line(s)")
done

if [ "${#BAD_SOURCES[@]}" -eq 0 ]; then
  pass "apt sources: all .list files valid"
else
  for msg in "${BAD_SOURCES[@]}"; do fail "apt source: $msg"; done
fi

UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c "/" || true)
if [ "$UPGRADABLE" -gt 0 ]; then
  warn "$UPGRADABLE packages can be upgraded — run: sudo apt upgrade"
else
  pass "All packages up to date"
fi

# ── Memory & Swap ─────────────────────────────────────────────────────────────
section "Memory"
SWAP_USED=$(free | awk '/^Swap:/{print $3}')
AVAILABLE=$(free -h | awk '/^Mem:/{print $7}')
SWAPPINESS=$(cat /proc/sys/vm/swappiness)

SWAP_USED_MB=$(( SWAP_USED / 1024 ))
if [ "$SWAP_USED_MB" -lt 10 ]; then
  pass "Swap used: ${SWAP_USED_MB}MB (clean)"
else
  warn "Swap in use: ${SWAP_USED_MB}MB — system may be under memory pressure"
fi

pass "RAM available: $AVAILABLE"

if [ "$SWAPPINESS" -le 20 ]; then
  pass "vm.swappiness: $SWAPPINESS (conservative)"
else
  warn "vm.swappiness: $SWAPPINESS — recommend ≤10 for server/SSD workloads"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [ "$ISSUES" -eq 0 ]; then
  echo "=== All checks passed — host is optimally configured ==="
  exit 0
else
  echo "=== $ISSUES issue(s) found — run: python3 lib/main.py --apply ==="
  exit 1
fi
