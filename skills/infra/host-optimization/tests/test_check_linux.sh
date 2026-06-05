#!/usr/bin/env bash
# Tests for check_linux.sh — syntax, structure, and key probe patterns.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

ok()   { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

# ── Syntax ────────────────────────────────────────────────────────────────────
if bash -n "$SKILL_DIR/lib/check_linux.sh" 2>/dev/null; then
  ok "syntax: check_linux.sh"
else
  fail "syntax: check_linux.sh"
fi

# ── Executable ────────────────────────────────────────────────────────────────
if [[ -x "$SKILL_DIR/lib/check_linux.sh" ]]; then
  ok "executable: check_linux.sh"
else
  fail "executable: check_linux.sh — missing +x"
fi

# ── Key check areas present ───────────────────────────────────────────────────
for pattern in \
  "scaling_governor" \
  "pci/devices.*power/control" \
  "CTXSW|SCHED_ERROR" \
  "nouveau.conf" \
  "kerneloops|colord|switcheroo" \
  "apt list --upgradable" \
  "vm.swappiness" \
  "PASS|WARN|FAIL"
do
  if grep -qE "$pattern" "$SKILL_DIR/lib/check_linux.sh"; then
    ok "check_linux.sh contains: $pattern"
  else
    fail "check_linux.sh missing: $pattern"
  fi
done

# ── Exit code behaviour ───────────────────────────────────────────────────────
# Script should exit non-zero when ISSUES > 0 (checked via variable logic)
if grep -q 'exit 1' "$SKILL_DIR/lib/check_linux.sh"; then
  ok "check_linux.sh: exits non-zero on issues"
else
  fail "check_linux.sh: should exit 1 when issues found"
fi

# ── tune_linux.sh key additions ───────────────────────────────────────────────
for pattern in \
  "schedutil" \
  "70-pci-pm.rules" \
  "nouveau" \
  "NvClkMode" \
  "kerneloops|colord|switcheroo" \
  "apt-get update"
do
  if grep -qE "$pattern" "$SKILL_DIR/lib/tune_linux.sh"; then
    ok "tune_linux.sh contains: $pattern"
  else
    fail "tune_linux.sh missing: $pattern"
  fi
done

# ── tune_linux.sh: does NOT use performance governor ─────────────────────────
if grep -q '"performance"' "$SKILL_DIR/lib/tune_linux.sh"; then
  fail "tune_linux.sh: still sets 'performance' governor — should be 'schedutil'"
else
  ok "tune_linux.sh: does not set deprecated 'performance' governor"
fi

# ── main.py: --check flag present ────────────────────────────────────────────
if grep -q "\-\-check" "$SKILL_DIR/lib/main.py"; then
  ok "main.py: --check flag present"
else
  fail "main.py: missing --check flag"
fi

# ── main.py: defaults to --check when no args ─────────────────────────────────
if grep -q "args.check = True" "$SKILL_DIR/lib/main.py"; then
  ok "main.py: defaults to --check when no args given"
else
  fail "main.py: should default to --check when no args given"
fi

# ── detect.py: GPU and temperature detection ──────────────────────────────────
for pattern in "get_gpu_info" "get_cpu_max_temp" "is_fermi" "sensors"; do
  if grep -q "$pattern" "$SKILL_DIR/lib/detect.py"; then
    ok "detect.py contains: $pattern"
  else
    fail "detect.py missing: $pattern"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
