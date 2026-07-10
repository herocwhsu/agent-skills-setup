#!/usr/bin/env bash
# Tests for the vpn lib scripts — syntax and security-relevant safety
# properties (key permissions, split-tunnel, non-destructive removal). Static
# checks only (no live WireGuard/network needed), matching the pattern
# established in host-optimization/tests/test_check_linux.sh.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

ok()   { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

# ── Syntax ──────────────────────────────────────────────────────────────────────
# No executable-bit check here: unlike host-optimization, vpn.sh dispatches to
# the others via `exec bash "$SKILL_LIB/setup.sh"` (confirmed in vpn.sh) and
# IMPL.md documents the same explicit `bash .../vpn.sh` invocation — all 6
# scripts are intentionally git-tracked as 100644, not 100755.
for script in setup.sh add-peer.sh status.sh remove.sh ddns.sh vpn.sh; do
  if bash -n "$SKILL_DIR/lib/$script" 2>/dev/null; then
    ok "syntax: $script"
  else
    fail "syntax: $script"
  fi
done

# ── setup.sh / add-peer.sh: secrets are chmod 600 ─────────────────────────────
for pattern in \
  "chmod 600 /etc/wireguard/server.key" \
  "chmod 600 /etc/wireguard/ddns.env" \
  "chmod 600 /etc/wireguard/server.env" \
  "chmod 600 /etc/wireguard/wg0.conf"
do
  if grep -qF "$pattern" "$SKILL_DIR/lib/setup.sh"; then
    ok "setup.sh chmods 600: $pattern"
  else
    fail "setup.sh missing chmod 600: $pattern"
  fi
done

for pattern in \
  "chmod 600 /etc/wireguard/peers/\${PEER_NAME}.key /etc/wireguard/peers/\${PEER_NAME}.psk" \
  "chmod 600 /etc/wireguard/peers/\${PEER_NAME}.conf"
do
  if grep -qF "$pattern" "$SKILL_DIR/lib/add-peer.sh"; then
    ok "add-peer.sh chmods 600: peer secret/conf files"
  else
    fail "add-peer.sh missing chmod 600 for: $pattern"
  fi
done

# ── setup.sh: does not unconditionally overwrite an existing wg0.conf ─────────
if grep -q 'if \[ -f /etc/wireguard/wg0.conf \]' "$SKILL_DIR/lib/setup.sh"; then
  ok "setup.sh: checks for existing wg0.conf before writing"
else
  fail "setup.sh: should guard against overwriting an existing wg0.conf"
fi

# ── add-peer.sh: requires setup to have run first ─────────────────────────────
for pattern in \
  '\[ -f /etc/wireguard/wg0.conf \] \|\| fail' \
  '\[ -f /etc/wireguard/ddns.env \] \|\| fail'
do
  if grep -qE "$pattern" "$SKILL_DIR/lib/add-peer.sh"; then
    ok "add-peer.sh: guards on prerequisite: $pattern"
  else
    fail "add-peer.sh missing prerequisite guard: $pattern"
  fi
done

# ── add-peer.sh: client config is split-tunnel, not full-tunnel ──────────────
if grep -q 'AllowedIPs = 10.8.0.0/24, \${LAN_SUBNET}' "$SKILL_DIR/lib/add-peer.sh"; then
  ok "add-peer.sh: client AllowedIPs is split-tunnel (VPN + LAN subnet only)"
else
  fail "add-peer.sh: client AllowedIPs should be split-tunnel, not full-tunnel"
fi
if grep -q '0\.0\.0\.0/0' "$SKILL_DIR/lib/add-peer.sh"; then
  fail "add-peer.sh: found 0.0.0.0/0 — would route all client traffic through the VPN (full-tunnel), contradicts the documented split-tunnel design"
else
  ok "add-peer.sh: does not route all traffic through the VPN (no 0.0.0.0/0)"
fi

# ── remove.sh: destructive action requires confirmation, preserves keys ──────
if grep -qE '\[y/N\]' "$SKILL_DIR/lib/remove.sh"; then
  ok "remove.sh: requires interactive confirmation before acting"
else
  fail "remove.sh: should require confirmation before removing the VPN"
fi
# A bare (non-echoed) "rm -rf /etc/wireguard" would be a live delete; the
# script should only ever mention it inside an echo (as a manual suggestion).
if grep -qE '^\s*(sudo )?rm -rf /etc/wireguard' "$SKILL_DIR/lib/remove.sh"; then
  fail "remove.sh: deletes /etc/wireguard unconditionally — keys should be preserved by default"
else
  ok "remove.sh: does not delete keys/configs by default (preserves /etc/wireguard)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
