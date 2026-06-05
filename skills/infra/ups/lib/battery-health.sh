#!/usr/bin/env bash
# Show battery longevity metrics and apply/verify optimal settings.
set -euo pipefail
UPS_NAME="apc-rs1500g"

if ! command -v upsc &>/dev/null; then
  echo "ERROR: NUT not installed. Run: /infra-ups setup" >&2
  exit 1
fi
if ! upsc "${UPS_NAME}@localhost" > /dev/null 2>&1; then
  echo "ERROR: Cannot reach ${UPS_NAME}@localhost. Is nut-server running?" >&2
  exit 1
fi

# ── Read current values ───────────────────────────────────────────────────────
raw=$(upsc "${UPS_NAME}@localhost" 2>/dev/null)
get() { echo "$raw" | grep "^${1}:" | awk '{print $2}'; }

CHARGE=$(get battery.charge)
CHARGE_LOW=$(get battery.charge.low)
RUNTIME=$(get battery.runtime)
RUNTIME_LOW=$(get battery.runtime.low)
SENSITIVITY=$(get input.sensitivity)
MFR_DATE=$(get battery.mfr.date)
LOAD=$(get ups.load)
STATUS=$(get ups.status)
BATT_VOLTAGE=$(get battery.voltage)
BATT_VOLTAGE_NOM=$(get battery.voltage.nominal)

echo "=== Battery Health — APC Back-UPS RS 1500G ==="
echo ""
printf "  %-32s %s%%\n"   "Current charge:"         "${CHARGE:-?}"
printf "  %-32s %s min\n" "Estimated runtime:"       "$(( ${RUNTIME:-0} / 60 ))"
printf "  %-32s %s%%\n"   "UPS load:"                "${LOAD:-?}"
printf "  %-32s %s\n"     "Status:"                  "${STATUS:-?}"
printf "  %-32s %s V (nominal %s V)\n" \
                          "Battery voltage:"         "${BATT_VOLTAGE:-?}" "${BATT_VOLTAGE_NOM:-?}"
printf "  %-32s %s\n"     "Battery install date:"    "${MFR_DATE:-?}"
echo ""
echo "--- Longevity Settings ---"
printf "  %-32s %s%% (target ≥30)\n"  "Shutdown threshold:"    "${CHARGE_LOW:-?}"
printf "  %-32s %s s (target ≥300)\n" "Runtime low alarm:"     "${RUNTIME_LOW:-?}"
printf "  %-32s %s (target: low)\n"   "Input sensitivity:"     "${SENSITIVITY:-?}"
echo ""

# ── Check & fix out-of-spec settings ─────────────────────────────────────────
FIXED=0
NUT_USER="upsmon"
NUT_PASS=$(sudo grep -E '^\s*password\s*=' /etc/nut/upsd.users 2>/dev/null \
           | awk -F'=' '{print $2}' | tr -d ' ')

fix() {
  local key=$1 val=$2 label=$3
  if upsrw -s "${key}=${val}" -u "$NUT_USER" -p "$NUT_PASS" \
      "${UPS_NAME}@localhost" 2>/dev/null; then
    echo "  [FIXED] $label → $val"
    FIXED=1
  else
    echo "  [WARN]  Could not set $key — check upsd.users has actions=SET"
  fi
}

[[ "${CHARGE_LOW:-10}" -lt 25 ]]  && fix battery.charge.low  30  "battery.charge.low"
[[ "${RUNTIME_LOW:-120}" -lt 250 ]] && fix battery.runtime.low 300 "battery.runtime.low"
[[ "$SENSITIVITY" != "low" ]]     && fix input.sensitivity   low "input.sensitivity"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [[ $FIXED -eq 0 ]]; then
  echo "  All longevity settings are optimal. No changes needed."
else
  echo "  Settings updated. Verify: upsc ${UPS_NAME}@localhost | grep battery"
fi
echo ""
echo "Tips:"
echo "  - Keep UPS below 25°C — every 10°C above halves SLA battery lifespan"
echo "  - Avoid deep discharge — SLA batteries degrade permanently below 30%"
echo "  - Run calibration at most once/year (each calibration = one deep cycle)"
echo "  - Replace battery when runtime drops below 50% of rated or every 3–5 years"
