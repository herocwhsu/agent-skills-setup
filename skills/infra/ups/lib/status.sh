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
  "battery\.charge|battery\.runtime|battery\.voltage|battery\.mfr\.date|input\.voltage|input\.sensitivity|output\.voltage|ups\.load|ups\.status|ups\.model|driver\.name|ups\.mfr" \
  | sort

echo ""
echo "=== Battery Health ==="
CHARGE=$(upsc "${UPS_NAME}@localhost" 2>/dev/null | grep "^battery\.charge:" | awk '{print $2}')
CHARGE_LOW=$(upsc "${UPS_NAME}@localhost" 2>/dev/null | grep "^battery\.charge\.low:" | awk '{print $2}')
RUNTIME=$(upsc "${UPS_NAME}@localhost" 2>/dev/null | grep "^battery\.runtime:" | awk '{print $2}')
SENSITIVITY=$(upsc "${UPS_NAME}@localhost" 2>/dev/null | grep "^input\.sensitivity:" | awk '{print $2}')
MFR_DATE=$(upsc "${UPS_NAME}@localhost" 2>/dev/null | grep "^battery\.mfr\.date:" | awk '{print $2}')

printf "  %-30s %s%%\n"   "Charge:" "${CHARGE:-?}"
printf "  %-30s %s%%\n"   "Shutdown threshold:" "${CHARGE_LOW:-?}"
printf "  %-30s %s min\n" "Runtime estimate:" "$(( ${RUNTIME:-0} / 60 ))"
printf "  %-30s %s\n"     "Sensitivity (transfers):" "${SENSITIVITY:-?}"
printf "  %-30s %s\n"     "Battery install date:" "${MFR_DATE:-?}"

[[ "${CHARGE_LOW:-10}" -gt 25 ]] \
  && echo "  [OK] Shutdown threshold >= 30% — deep discharge protected" \
  || echo "  [WARN] Shutdown threshold < 25% — run setup to fix"
[[ "$SENSITIVITY" == "low" ]] \
  && echo "  [OK] Sensitivity=low — fewer unnecessary battery transfers" \
  || echo "  [WARN] Sensitivity not low — consider: upsrw -s input.sensitivity=low"

echo ""
echo "NUT services:"
for svc in nut-driver.target nut-server nut-monitor; do
  STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
  printf "  %-25s %s\n" "$svc" "$STATUS"
done
