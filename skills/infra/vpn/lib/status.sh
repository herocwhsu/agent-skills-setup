#!/usr/bin/env bash
set -euo pipefail

[ -f /etc/wireguard/ddns.env ] && source /etc/wireguard/ddns.env || true

echo "=== WireGuard VPN Status ==="
echo ""

# ── Service state ─────────────────────────────────────────────────────────────
STATE=$(systemctl is-active wg-quick@wg0 2>/dev/null || echo "inactive")
echo "  Service:   wg-quick@wg0 → ${STATE}"
[ "$STATE" != "active" ] && echo "  [WARN] VPN is not running. Start: sudo systemctl start wg-quick@wg0" && exit 0

# ── Interface ─────────────────────────────────────────────────────────────────
echo ""
sudo wg show wg0 2>/dev/null || echo "  [WARN] Cannot read wg0 interface"

# ── IP vs DNS ─────────────────────────────────────────────────────────────────
echo ""
echo "--- DDNS ---"
CURRENT_IP=$(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null || echo "unavailable")
if [ -n "${CF_RECORD:-}" ] && [ -n "${CF_TOKEN:-}" ] && [ -n "${CF_ZONE_ID:-}" ]; then
  DNS_IP=$(curl -sf --max-time 5 \
    -H "Authorization: Bearer ${CF_TOKEN}" \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${CF_RECORD}" \
    | python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['content'] if r else 'no record')" 2>/dev/null || echo "error")
  printf "  %-20s %s\n" "Public IP:" "$CURRENT_IP"
  printf "  %-20s %s\n" "${CF_RECORD}:" "$DNS_IP"
  [ "$CURRENT_IP" = "$DNS_IP" ] && echo "  [PASS] DNS record is current" \
                                 || echo "  [WARN] DNS mismatch — cron will fix within 5 min"
else
  printf "  %-20s %s\n" "Public IP:" "$CURRENT_IP"
  echo "  (DDNS not configured — run /infra-vpn setup)"
fi

# ── Last DDNS log ─────────────────────────────────────────────────────────────
if [ -f /var/log/wg-ddns.log ]; then
  echo ""
  echo "--- Recent DDNS updates ---"
  tail -5 /var/log/wg-ddns.log
fi
