#!/usr/bin/env bash
# Set up WireGuard VPN server with Cloudflare DDNS.
set -euo pipefail

info() { echo "  [INFO]  $*"; }
pass() { echo "  [PASS]  $*"; }
fail() { echo "  [FAIL]  $*"; exit 1; }
ask()  { read -rp "  >>> $* " ans; echo "$ans"; }

echo "=== WireGuard VPN Server Setup ==="
echo ""

# ── Pre-flight ────────────────────────────────────────────────────────────────
command -v wg &>/dev/null || sudo apt-get install -y wireguard-tools > /dev/null
command -v qrencode &>/dev/null || sudo apt-get install -y qrencode > /dev/null

# Load WireGuard kernel module
sudo modprobe wireguard 2>/dev/null || true
if ! lsmod | grep -q wireguard; then
  fail "WireGuard kernel module not available. Run: sudo apt install linux-modules-extra-$(uname -r)"
fi
pass "WireGuard kernel module loaded"

# ── Detect LAN interface + subnet ─────────────────────────────────────────────
LAN_IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
LAN_IP_CIDR=$(ip -o -f inet addr show "$LAN_IFACE" | awk '{print $4}' | head -1)
LAN_IP=$(echo "$LAN_IP_CIDR" | cut -d/ -f1)
LAN_SUBNET=$(python3 -c "import ipaddress; print(str(ipaddress.ip_network('${LAN_IP_CIDR}', strict=False)))")
info "LAN interface: ${LAN_IFACE}  subnet: ${LAN_SUBNET}"

# ── Cloudflare DDNS credentials ───────────────────────────────────────────────
echo ""
echo "--- Cloudflare DDNS credentials ---"
echo "  Create a token at: https://dash.cloudflare.com/profile/api-tokens"
echo "  Permissions: Zone → DNS → Edit (scope to your zone only)"
echo ""
CF_TOKEN=$(ask "Cloudflare API token:")
CF_ZONE_ID=$(ask "Zone ID (from Cloudflare dashboard → your domain → Overview):")
CF_RECORD=$(ask "Full subdomain for VPN endpoint (e.g. vpn.example.com):")
[ -z "$CF_RECORD" ] && { echo "  [FAIL]  Subdomain is required"; exit 1; }

sudo mkdir -p /etc/wireguard
sudo tee /etc/wireguard/ddns.env > /dev/null <<EOF
CF_TOKEN=${CF_TOKEN}
CF_ZONE_ID=${CF_ZONE_ID}
CF_RECORD=${CF_RECORD}
EOF
sudo chmod 600 /etc/wireguard/ddns.env

sudo tee /etc/wireguard/server.env > /dev/null <<EOF
LAN_IFACE=${LAN_IFACE}
LAN_SUBNET=${LAN_SUBNET}
EOF
sudo chmod 600 /etc/wireguard/server.env
pass "DDNS credentials saved to /etc/wireguard/ddns.env"

# ── Server keypair ────────────────────────────────────────────────────────────
echo ""
echo "--- Generating server keypair ---"
if [ -f /etc/wireguard/server.key ]; then
  info "Server key already exists — skipping keygen"
else
  wg genkey | sudo tee /etc/wireguard/server.key > /dev/null
  sudo chmod 600 /etc/wireguard/server.key
  sudo cat /etc/wireguard/server.key | wg pubkey | sudo tee /etc/wireguard/server.pub > /dev/null
  pass "Server keypair generated"
fi
SERVER_PRIVKEY=$(sudo cat /etc/wireguard/server.key)
SERVER_PUBKEY=$(sudo cat /etc/wireguard/server.pub)
info "Server public key: ${SERVER_PUBKEY}"

# ── wg0.conf ──────────────────────────────────────────────────────────────────
echo ""
echo "--- Writing /etc/wireguard/wg0.conf ---"
if [ -f /etc/wireguard/wg0.conf ]; then
  info "wg0.conf already exists — not overwriting. Edit manually or run remove first."
else
  sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = ${SERVER_PRIVKEY}
# PostUp/Down manage UFW masquerade for LAN forwarding
PostUp   = iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${LAN_IFACE} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o ${LAN_IFACE} -j MASQUERADE

# Peers added by: /infra-vpn add-peer <name>
EOF
  sudo chmod 600 /etc/wireguard/wg0.conf
  pass "wg0.conf written"
fi

# ── IP forwarding ─────────────────────────────────────────────────────────────
echo ""
echo "--- Enabling IP forwarding ---"
sudo tee /etc/sysctl.d/99-wireguard.conf > /dev/null <<'EOF'
net.ipv4.ip_forward=1
EOF
sudo sysctl --system > /dev/null 2>&1
pass "IP forwarding enabled"

# ── UFW ───────────────────────────────────────────────────────────────────────
echo ""
echo "--- UFW rules ---"
if ! sudo ufw status | grep -q "51820"; then
  sudo ufw allow 51820/udp comment "WireGuard VPN"
  pass "UFW: allowed UDP 51820"
else
  info "UFW rule for 51820/udp already present"
fi

# ── Enable service ────────────────────────────────────────────────────────────
echo ""
echo "--- Enabling wg-quick@wg0 ---"
sudo systemctl enable --now wg-quick@wg0
pass "wg-quick@wg0 enabled and started"

# ── DDNS cron ─────────────────────────────────────────────────────────────────
echo ""
echo "--- Installing DDNS cron ---"
DDNS_SCRIPT="$(cd "$(dirname "$0")" && pwd)/ddns.sh"
sudo tee /etc/cron.d/wg-ddns > /dev/null <<EOF
*/5 * * * * root bash ${DDNS_SCRIPT} >> /var/log/wg-ddns.log 2>&1
EOF
sudo chmod 644 /etc/cron.d/wg-ddns
pass "DDNS cron installed (/etc/cron.d/wg-ddns, every 5 min)"

# Run once now to create the DNS record
info "Running DDNS update now..."
sudo bash "$DDNS_SCRIPT" && pass "DNS record created/updated for ${CF_RECORD}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Setup complete ==="
echo ""
echo "  Server public key:  ${SERVER_PUBKEY}"
echo "  VPN endpoint:       ${CF_RECORD}:51820"
echo "  VPN subnet:         10.8.0.0/24"
echo ""
echo "  Next steps:"
echo "  1. Port-forward UDP 51820 → ${LAN_IP} on your router"
echo "  2. Add peers:  /infra-vpn add-peer laptop1"
echo "                 /infra-vpn add-peer laptop2"
echo "                 /infra-vpn add-peer remotehost"
echo ""
