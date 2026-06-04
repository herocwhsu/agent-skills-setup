#!/usr/bin/env bash
# UPS skill unit tests — no UPS or NUT installation required.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

ok()   { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

# ── Syntax checks ─────────────────────────────────────────────────────────────
for f in lib/ups.sh lib/install.sh lib/shutdown.sh lib/status.sh; do
  if bash -n "$SKILL_DIR/$f" 2>/dev/null; then
    ok "syntax: $f"
  else
    fail "syntax: $f"
  fi
done

# ── Executable bits ───────────────────────────────────────────────────────────
for f in lib/ups.sh lib/install.sh lib/shutdown.sh lib/status.sh; do
  if [[ -x "$SKILL_DIR/$f" ]]; then
    ok "executable: $f"
  else
    fail "executable: $f — missing +x"
  fi
done

# ── ups.sh: unknown subcommand exits non-zero ─────────────────────────────────
if ! bash "$SKILL_DIR/lib/ups.sh" __bogus__ 2>/dev/null; then
  ok "ups.sh: unknown subcommand exits non-zero"
else
  fail "ups.sh: unknown subcommand should exit non-zero"
fi

# ── ups.sh: test-shutdown subcommand works without NUT installed ─────────────
if bash "$SKILL_DIR/lib/ups.sh" test-shutdown 2>/dev/null | grep -q "DRY RUN"; then
  ok "ups.sh test-shutdown: dry-run output contains 'DRY RUN'"
else
  fail "ups.sh test-shutdown: expected 'DRY RUN' in output"
fi

# ── ups.sh: help/no-arg prints usage without error ───────────────────────────
if bash "$SKILL_DIR/lib/ups.sh" 2>/dev/null; then
  ok "ups.sh: no-arg exits zero"
else
  fail "ups.sh: no-arg should exit zero (prints usage)"
fi

# ── shutdown.sh: double-run protection (lockfile logic) ──────────────────────
LOCKFILE=/var/run/ups-shutdown.lock
if sudo touch "$LOCKFILE" 2>/dev/null; then
  if sudo bash "$SKILL_DIR/lib/shutdown.sh" test 2>&1 | grep -q "already in progress"; then
    ok "shutdown.sh: double-run protection works"
  else
    fail "shutdown.sh: double-run protection not working"
  fi
  sudo rm -f "$LOCKFILE"
else
  echo "SKIP: double-run test (no write access to /var/run)"
fi

# ── install.sh: key config strings are present ───────────────────────────────
for pattern in "usbhid-ups" "upssched" "START-TIMER onbatt 60" "CANCEL-TIMER onbatt" "LOWBATT.*EXECUTE"; do
  if grep -qP "$pattern" "$SKILL_DIR/lib/install.sh"; then
    ok "install.sh contains: $pattern"
  else
    fail "install.sh missing: $pattern"
  fi
done

# ── install.sh: uses primary not master (NUT 2.8+) ───────────────────────────
if grep -q "upsmon primary" "$SKILL_DIR/lib/install.sh"; then
  ok "install.sh: uses 'upsmon primary' (NUT 2.8+ syntax)"
else
  fail "install.sh: should use 'upsmon primary' not 'upsmon master'"
fi

# ── install.sh: idempotency grep uses correct pattern ────────────────────────
if grep -qE 'grep.*\\s\*password' "$SKILL_DIR/lib/install.sh"; then
  ok "install.sh: password idempotency grep uses whitespace-aware pattern"
else
  fail "install.sh: password idempotency grep may not match NUT's indented format"
fi

# ── shutdown.sh: all stop stages present ─────────────────────────────────────
for pattern in "k3s.service" "docker ps -q" "containerd.service" "zpool sync" "drop_caches" "systemctl poweroff"; do
  if grep -q "$pattern" "$SKILL_DIR/lib/shutdown.sh"; then
    ok "shutdown.sh contains: $pattern"
  else
    fail "shutdown.sh missing: $pattern"
  fi
done

# ── shutdown.sh: uses -T flag (not --timeout) ────────────────────────────────
if grep -q "\-T \${TIMEOUT_K3S}" "$SKILL_DIR/lib/shutdown.sh"; then
  ok "shutdown.sh: uses -T flag for systemctl timeout"
else
  fail "shutdown.sh: should use '-T \${TIMEOUT_K3S}' not '--timeout'"
fi

# ── shutdown.sh: atomic lockfile (noclobber pattern) ─────────────────────────
if grep -q "noclobber" "$SKILL_DIR/lib/shutdown.sh"; then
  ok "shutdown.sh: uses atomic noclobber lockfile"
else
  fail "shutdown.sh: should use 'set -o noclobber' for atomic lockfile"
fi

# ── ups.sh: remove uses purge ────────────────────────────────────────────────
if grep -q "apt-get purge" "$SKILL_DIR/lib/ups.sh"; then
  ok "ups.sh: remove uses apt-get purge"
else
  fail "ups.sh: remove should use apt-get purge not remove"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
