#!/usr/bin/env bash
# Claude Code Notification hook — push via ntfy
# NTFY_URL and NTFY_TOKEN are set during setup-host.sh

NTFY_URL="${NTFY_URL:-}"
NTFY_TOKEN="${NTFY_TOKEN:-}"

if [ -z "$NTFY_URL" ] || [ -z "$NTFY_TOKEN" ]; then
  exit 0
fi

msg=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('message', 'Waiting for you'))
except Exception:
    print('Waiting for you')
" 2>/dev/null || echo "Waiting for you")

curl -s -o /dev/null \
  -X POST "$NTFY_URL" \
  -H "Authorization: Bearer $NTFY_TOKEN" \
  -H "Title: Claude Code" \
  -H "Tags: bell" \
  -d "$msg"
