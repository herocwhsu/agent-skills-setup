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
