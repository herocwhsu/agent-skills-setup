#!/usr/bin/env bash
# credentials/confluence.sh — manage Confluence credentials
# Usage: bash confluence.sh <add|update|delete|list>
source "$(dirname "$0")/_store.sh"

ACTION="${1:-}"
if [[ -z "$ACTION" ]]; then
  echo "Usage: $0 <add|update|delete|list>"; exit 1
fi

case "$ACTION" in
  add|update)
    read -rp  "Confluence URL (e.g. https://confluence.example.com): " URL
    read -rp  "Username: " USER
    read -rsp "Password (hidden): " PASS; echo
    SLUG="confluence-$(echo "$URL" | sed 's|https\?://||;s|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//')"
    store_credential "$SLUG" "$USER" "$PASS"
    add_profile_export "$SLUG" "$USER" "CONFLUENCE_PASS"
    echo "  ✓ Confluence credentials saved (env: CONFLUENCE_PASS)"
    ;;
  delete)
    read -rp "Confluence URL: " URL
    read -rp "Username: " USER
    SLUG="confluence-$(echo "$URL" | sed 's|https\?://||;s|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//')"
    delete_credential "$SLUG" "$USER"
    remove_profile_export "$SLUG"
    ;;
  list)
    list_credentials
    ;;
  *)
    echo "Unknown action: $ACTION. Use add|update|delete|list."; exit 1 ;;
esac
