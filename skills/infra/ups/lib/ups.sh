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
