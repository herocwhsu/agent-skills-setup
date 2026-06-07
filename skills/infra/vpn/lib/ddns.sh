#!/usr/bin/env bash
# Cloudflare DDNS updater for vpn.example.com
# Runs every 5 min via /etc/cron.d/wg-ddns
set -euo pipefail

ENV_FILE="/etc/wireguard/ddns.env"
[ -f "$ENV_FILE" ] || { echo "$(date) ERROR: $ENV_FILE not found"; exit 1; }
source "$ENV_FILE"

CURRENT_IP=$(curl -sf --max-time 10 https://api.ipify.org) \
  || { echo "$(date) ERROR: Could not get public IP"; exit 1; }

# Get current DNS record value + record ID from Cloudflare
CF_RESPONSE=$(curl -sf --max-time 10 \
  -H "Authorization: Bearer ${CF_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${CF_RECORD}")

DNS_IP=$(echo "$CF_RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['content'] if r else '')" 2>/dev/null || echo "")
RECORD_ID=$(echo "$CF_RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['id'] if r else '')" 2>/dev/null || echo "")

if [ "$CURRENT_IP" = "$DNS_IP" ]; then
  # No change — silent exit (cron log stays clean)
  exit 0
fi

echo "$(date) IP changed: ${DNS_IP:-<none>} → ${CURRENT_IP}"

if [ -z "$RECORD_ID" ]; then
  # Create new A record
  curl -sf --max-time 10 \
    -X POST \
    -H "Authorization: Bearer ${CF_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
    --data "{\"type\":\"A\",\"name\":\"${CF_RECORD}\",\"content\":\"${CURRENT_IP}\",\"ttl\":120,\"proxied\":false}" \
    > /dev/null
  echo "$(date) Created A record: ${CF_RECORD} → ${CURRENT_IP}"
else
  # Update existing A record
  curl -sf --max-time 10 \
    -X PATCH \
    -H "Authorization: Bearer ${CF_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
    --data "{\"content\":\"${CURRENT_IP}\"}" \
    > /dev/null
  echo "$(date) Updated A record: ${CF_RECORD} → ${CURRENT_IP}"
fi
