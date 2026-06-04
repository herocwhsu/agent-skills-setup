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
if ! ( set -o noclobber; echo $$ > "$LOCKFILE" ) 2>/dev/null; then
  log "Shutdown already in progress (lockfile exists). Exiting."
  exit 0
fi
trap 'rm -f "$LOCKFILE"' EXIT

# ── 1. Stop k3s (Kubernetes) ─────────────────────────────────────────────────
if systemctl is-active --quiet k3s.service 2>/dev/null; then
  log "Stopping k3s (timeout ${TIMEOUT_K3S}s)..."
  systemctl stop k3s.service -T ${TIMEOUT_K3S} || warn "k3s stop timed out"
else
  log "k3s not running, skipping."
fi

# ── 2. Stop Docker containers then Docker daemon ─────────────────────────────
if systemctl is-active --quiet docker.service 2>/dev/null; then
  log "Stopping all Docker containers (timeout ${TIMEOUT_DOCKER}s each)..."
  if command -v docker &>/dev/null; then
    CONTAINERS=$(docker ps -q 2>/dev/null || true)
    if [[ -n "$CONTAINERS" ]]; then
      docker stop --time=$TIMEOUT_DOCKER $CONTAINERS 2>/dev/null || true
    fi
  fi
  log "Stopping Docker daemon..."
  systemctl stop docker.service docker.socket -T ${TIMEOUT_DOCKER} 2>/dev/null || warn "docker stop failed"
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
