#!/usr/bin/env bash
# credentials/apidog.sh — manage Apidog credentials
# Usage: bash apidog.sh <add|update|delete|list|verify>
source "$(dirname "$0")/_store.sh"

ACTION="${1:-}"
if [[ -z "$ACTION" ]]; then
  echo "Usage: $0 <add|update|delete|list|verify>"; exit 1
fi

SLUG="apidog"

case "$ACTION" in
  add|update)
    read -rp  "Apidog username / email: " USER
    read -rsp "API token (hidden): " PASS; echo
    store_credential "$SLUG" "$USER" "$PASS"
    echo "  ✓ Apidog credentials saved"
    echo "  Use in scripts: TOKEN=\$($(read_credential_inline "$SLUG" "$USER"))"
    ;;
  delete)
    read -rp "Apidog username / email: " USER
    delete_credential "$SLUG" "$USER"
    ;;
  list)
    list_credentials
    ;;
  verify)
    read -rp "Apidog username / email: " USER
    verify_credential "$SLUG" "$USER"
    ;;
  *)
    echo "Unknown action: $ACTION. Use add|update|delete|list|verify."; exit 1 ;;
esac
