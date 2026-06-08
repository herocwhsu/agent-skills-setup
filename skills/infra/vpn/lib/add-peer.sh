#!/usr/bin/env bash
# Add a WireGuard peer: generate keypair+PSK, append to wg0.conf, print config+QR.
set -euo pipefail

PEER_NAME="${1:-}"
[ -z "$PEER_NAME" ] && { echo "Usage: add-peer.sh <name>  (e.g. laptop1)"; exit 1; }

info() { echo "  [INFO]  $*"; }
pass() { echo "  [PASS]  $*"; }
fail() { echo "  [FAIL]  $*"; exit 1; }

[ -f /etc/wireguard/wg0.conf ] || fail "wg0.conf not found. Run /infra-vpn setup first."
[ -f /etc/wireguard/ddns.env ] || fail "ddns.env not found. Run /infra-vpn setup first."

# Load DDNS env for endpoint hostname and server env for LAN subnet
source /etc/wireguard/ddns.env 2>/dev/null || true
source /etc/wireguard/server.env 2>/dev/null || true
LAN_SUBNET="${LAN_SUBNET:-10.8.0.0/24}"

echo "=== Adding VPN peer: ${PEER_NAME} ==="
echo ""

# ── Assign next available VPN IP ──────────────────────────────────────────────
USED=$(sudo grep -oP '10\.8\.0\.\K[0-9]+' /etc/wireguard/wg0.conf | sort -n)
NEXT=2
for ip in $USED; do [ "$ip" -ge "$NEXT" ] && NEXT=$(( ip + 1 )); done
PEER_IP="10.8.0.${NEXT}"
info "Assigning VPN IP: ${PEER_IP}"

# ── Generate keypair + PSK ────────────────────────────────────────────────────
sudo mkdir -p /etc/wireguard/peers
PEER_PRIVKEY=$(wg genkey)
PEER_PUBKEY=$(echo "$PEER_PRIVKEY" | wg pubkey)
PEER_PSK=$(wg genpsk)
SERVER_PUBKEY=$(sudo cat /etc/wireguard/server.pub)

echo "$PEER_PRIVKEY" | sudo tee /etc/wireguard/peers/${PEER_NAME}.key > /dev/null
echo "$PEER_PUBKEY"  | sudo tee /etc/wireguard/peers/${PEER_NAME}.pub > /dev/null
echo "$PEER_PSK"     | sudo tee /etc/wireguard/peers/${PEER_NAME}.psk > /dev/null
sudo chmod 600 /etc/wireguard/peers/${PEER_NAME}.key /etc/wireguard/peers/${PEER_NAME}.psk
pass "Keypair + PSK generated"

# ── Append peer to wg0.conf ───────────────────────────────────────────────────
sudo tee -a /etc/wireguard/wg0.conf > /dev/null <<EOF

# Peer: ${PEER_NAME}
[Peer]
PublicKey = ${PEER_PUBKEY}
PresharedKey = ${PEER_PSK}
AllowedIPs = ${PEER_IP}/32
EOF

# Live reload without dropping existing connections
sudo wg syncconf wg0 <(sudo wg-quick strip wg0) 2>/dev/null \
  || sudo systemctl reload wg-quick@wg0 2>/dev/null \
  || info "Reload failed — restart with: sudo systemctl restart wg-quick@wg0"
pass "Peer added to wg0 (live reload)"

# ── Build client config ───────────────────────────────────────────────────────
[ -z "${CF_RECORD:-}" ] && fail "CF_RECORD not set in /etc/wireguard/ddns.env — re-run setup"
ENDPOINT="${CF_RECORD}:51820"

CLIENT_CONF="[Interface]
Address = ${PEER_IP}/24
PrivateKey = ${PEER_PRIVKEY}
DNS = 1.1.1.1

[Peer]
# WireGuard server
PublicKey = ${SERVER_PUBKEY}
PresharedKey = ${PEER_PSK}
Endpoint = ${ENDPOINT}
# Split tunnel: home LAN + VPN subnet only
AllowedIPs = 10.8.0.0/24, ${LAN_SUBNET}
PersistentKeepalive = 25"

# ── Output ────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Client config for: ${PEER_NAME}  (${PEER_IP})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "$CLIENT_CONF"
echo ""

# Save conf file
sudo tee /etc/wireguard/peers/${PEER_NAME}.conf > /dev/null <<< "$CLIENT_CONF"
sudo chmod 600 /etc/wireguard/peers/${PEER_NAME}.conf
info "Config saved to /etc/wireguard/peers/${PEER_NAME}.conf"

# QR code for mobile/laptop app
if command -v qrencode &>/dev/null; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  QR code (scan with WireGuard app):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$CLIENT_CONF" | qrencode -t ansiutf8
fi

echo ""
echo "  Install on Linux peer:"
echo "    sudo apt install wireguard-tools"
echo "    sudo cp <conf-file> /etc/wireguard/wg0.conf && sudo chmod 600 /etc/wireguard/wg0.conf"
echo "    sudo systemctl enable --now wg-quick@wg0"
echo ""
echo "  macOS/Windows/Mobile: import the conf file or scan QR in the WireGuard app"
echo ""
