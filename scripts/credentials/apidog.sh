#!/usr/bin/env bash
# credentials/apidog.sh — manage Apidog credentials
# Usage: bash apidog.sh <add|update|delete|list>
source "$(dirname "$0")/_store.sh"

ACTION="${1:-}"
if [[ -z "$ACTION" ]]; then
  echo "Usage: $0 <add|update|delete|list>"; exit 1
fi

# Apidog uses a fixed service slug (no per-URL variation)
SLUG="apidog"

case "$ACTION" in
  add|update)
    read -rp  "Apidog username / email: " USER
    read -rsp "API token (hidden): " PASS; echo
    store_credential "$SLUG" "$USER" "$PASS"
    add_profile_export "$SLUG" "$USER" "APIDOG_TOKEN"
    echo "  ✓ Apidog credentials saved (env: APIDOG_TOKEN)"
    ;;
  delete)
    read -rp "Apidog username / email: " USER
    delete_credential "$SLUG" "$USER"
    remove_profile_export "$SLUG"
    ;;
  list)
    list_credentials
    ;;
  *)
    echo "Unknown action: $ACTION. Use add|update|delete|list."; exit 1 ;;
esac
