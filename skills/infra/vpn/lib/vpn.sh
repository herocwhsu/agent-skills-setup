#!/usr/bin/env bash
# /infra-vpn dispatcher
set -euo pipefail
SKILL_LIB="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: vpn.sh <subcommand> [args]"
  echo "  setup             Generate keys, configure wg0, UFW, DDNS cron"
  echo "  add-peer <name>   Add a new peer and print its config + QR code"
  echo "  status            Show active peers, handshakes, IP vs DNS"
  echo "  remove            Tear down VPN, remove UFW rules and cron"
}

case "${1:-}" in
  setup)        exec bash "$SKILL_LIB/setup.sh" ;;
  add-peer)     exec bash "$SKILL_LIB/add-peer.sh" "${2:-}" ;;
  status)       exec bash "$SKILL_LIB/status.sh" ;;
  remove)       exec bash "$SKILL_LIB/remove.sh" ;;
  help|--help|-h|"") usage ;;
  *) echo "Unknown subcommand: $1" >&2; usage >&2; exit 1 ;;
esac
