#!/usr/bin/env bash
# Walk through the full battery replacement procedure:
#   1. Update battery.date in UPS EEPROM via apctest
#   2. Prompt to run a deep calibration test
#   3. Verify runtime estimate after recharge
set -euo pipefail
UPS_NAME="apc-rs1500g"
TODAY=$(date +%Y/%m/%d)

info()  { echo "  [INFO]  $*"; }
warn()  { echo "  [WARN]  $*"; }
pass()  { echo "  [PASS]  $*"; }
fail()  { echo "  [FAIL]  $*"; exit 1; }
ask()   { read -rp "  >>> $* [y/N] " ans; [[ "${ans,,}" == "y" ]]; }

echo "=== UPS Battery Replacement Helper ==="
echo ""

# ── Pre-flight ────────────────────────────────────────────────────────────────
command -v upsc &>/dev/null || fail "NUT not installed. Run: /infra-ups setup"
upsc "${UPS_NAME}@localhost" > /dev/null 2>&1 || fail "Cannot reach ${UPS_NAME}@localhost"

raw=$(upsc "${UPS_NAME}@localhost" 2>/dev/null)
get() { echo "$raw" | grep "^${1}:" | awk '{print $2}'; }

BATT_DATE=$(get battery.date)
MFR_DATE=$(get battery.mfr.date)
RUNTIME_MIN=$(( $(get battery.runtime) / 60 ))
CHARGE=$(get battery.charge)

echo "  Current battery.date:     ${BATT_DATE:-unknown} (UPS EEPROM — age-derating source)"
echo "  battery.mfr.date:         ${MFR_DATE:-unknown} (new battery manufacture date)"
echo "  Runtime estimate:         ${RUNTIME_MIN} min at $(get ups.load)% load"
echo "  Charge:                   ${CHARGE}%"
echo ""

# ── Step 1: Update battery.date ───────────────────────────────────────────────
echo "--- Step 1: Update battery.date to today (${TODAY}) ---"
echo ""
info "battery.date is stored in UPS EEPROM and is not writable via NUT upsrw."
info "Requires apctest (apcupsd package). NUT will be stopped temporarily."
echo ""

if ! ask "Proceed with updating battery.date?"; then
  warn "Skipping battery.date update."
else
  info "Stopping NUT services..."
  sudo systemctl stop nut-monitor nut-server nut-driver.target 2>/dev/null || true
  sleep 2

  info "Installing apcupsd (will NOT enable its service)..."
  sudo apt-get install -y apcupsd > /dev/null 2>&1
  sudo systemctl disable apcupsd 2>/dev/null || true
  sudo systemctl stop apcupsd 2>/dev/null || true

  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────┐"
  echo "  │  apctest will open interactively.                           │"
  echo "  │                                                             │"
  echo "  │  Navigate to:                                               │"
  echo "  │    6) View/Change battery parameters                        │"
  echo "  │    → Battery date: set to ${TODAY}                    │"
  echo "  │  Then quit apctest (option Q).                              │"
  echo "  └─────────────────────────────────────────────────────────────┘"
  echo ""
  read -rp "  Press ENTER to launch apctest..."
  sudo apctest || warn "apctest exited with error — battery.date may not have been updated"

  info "Removing apcupsd..."
  sudo apt-get remove -y apcupsd > /dev/null 2>&1

  info "Restarting NUT services..."
  sudo systemctl start nut-driver.target
  sleep 3
  sudo systemctl start nut-server nut-monitor
  sleep 2

  NEW_DATE=$(upsc "${UPS_NAME}@localhost" 2>/dev/null | grep "^battery.date:" | awk '{print $2}')
  if [[ "$NEW_DATE" == "$TODAY" ]]; then
    pass "battery.date updated to ${TODAY}"
  else
    warn "battery.date is now: ${NEW_DATE:-unknown} (expected ${TODAY})"
    warn "If wrong, re-run this step or update via APC PowerChute on Windows."
  fi
fi

echo ""

# ── Step 2: Deep calibration test ─────────────────────────────────────────────
echo "--- Step 2: Deep calibration test ---"
echo ""
info "Discharges battery to ~25%, then recharges. Takes ~4-6 hours total."
info "The machine runs on battery during discharge (~30-60 min at current load)."
info "Runtime estimate will be accurate after recharge completes."
warn "Schedule this during a quiet window. k3s/Docker workloads will continue but"
warn "the machine will shut down if battery hits the low threshold."
echo ""

if ! ask "Run deep calibration test now?"; then
  info "Skipping calibration. Run manually when ready:"
  echo ""
  echo "    NUT_PASS=\$(sudo grep -E '^\s*password\s*=' /etc/nut/upsd.users | awk -F= '{print \$2}' | tr -d ' ')"
  echo "    upscmd -u upsmon -p \"\$NUT_PASS\" ${UPS_NAME} test.battery.start.deep"
  echo "    watch -n5 \"upsc ${UPS_NAME} | grep -E 'battery.charge|battery.runtime|ups.status|ups.test'\""
  echo ""
else
  NUT_PASS=$(sudo grep -E '^\s*password\s*=' /etc/nut/upsd.users 2>/dev/null \
             | awk -F'=' '{print $2}' | tr -d ' ')
  if [[ -z "$NUT_PASS" ]]; then
    fail "Could not read upsmon password from /etc/nut/upsd.users"
  fi

  info "Starting deep battery test..."
  upscmd -u upsmon -p "$NUT_PASS" "${UPS_NAME}" test.battery.start.deep
  pass "Test started. Monitor with:"
  echo ""
  echo "    watch -n5 \"upsc ${UPS_NAME} | grep -E 'battery.charge|battery.runtime|ups.status|ups.test'\""
  echo ""
  info "Runtime estimate updates automatically after recharge completes."
fi

echo ""

# ── Step 3: Verify ────────────────────────────────────────────────────────────
echo "--- Step 3: Verify (run after recharge completes) ---"
echo ""
raw2=$(upsc "${UPS_NAME}@localhost" 2>/dev/null)
get2() { echo "$raw2" | grep "^${1}:" | awk '{print $2}'; }
RUNTIME2_MIN=$(( $(get2 battery.runtime) / 60 ))
LOAD2=$(get2 ups.load)

printf "  %-32s %s min\n" "Current runtime estimate:" "${RUNTIME2_MIN}"
printf "  %-32s %s%%\n"   "Current load:"             "${LOAD2}"
echo ""

if [[ $RUNTIME2_MIN -ge 120 ]]; then
  pass "Runtime ≥ 120 min — battery is performing as expected."
elif [[ $RUNTIME2_MIN -ge 80 ]]; then
  warn "Runtime ${RUNTIME2_MIN} min — acceptable but below ideal."
  warn "If calibration test is still in progress, re-check after full recharge."
  warn "Also verify the physical battery Ah rating matches the original (should be 9Ah)."
else
  warn "Runtime ${RUNTIME2_MIN} min — lower than expected."
  warn "Check physical battery label: a 7Ah battery gives ~22% less runtime than 9Ah."
  warn "If battery.date is still wrong, the derating may still be active."
fi

echo ""
echo "Tips:"
echo "  - New SLA batteries reach full capacity after 2-3 charge/discharge cycles"
echo "  - Run calibration at most once/year (each deep cycle ages the battery slightly)"
echo "  - Replace battery when runtime drops below 50% of rated or every 3-5 years"
echo "  - Keep UPS below 25°C — every 10°C above halves SLA battery lifespan"
