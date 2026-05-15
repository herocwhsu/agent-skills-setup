#!/usr/bin/env bash
# credentials/jira.sh — manage Jira credentials
# Usage: bash jira.sh <add|update|delete|list|verify>
source "$(dirname "$0")/_store.sh"

ACTION="${1:-}"
if [[ -z "$ACTION" ]]; then
  echo "Usage: $0 <add|update|delete|list|verify>"; exit 1
fi

case "$ACTION" in
  add|update)
    read -rp  "Jira URL (e.g. https://jira.example.com): " URL
    read -rp  "Username: " USER
    read -rsp "Password / API token (hidden): " PASS; echo
    SLUG="jira-$(echo "$URL" | sed 's|https\?://||;s|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//')"
    store_credential "$SLUG" "$USER" "$PASS"
    echo "  ✓ Jira credentials saved"
    echo "  Use in scripts: PASS=\$($(read_credential_inline "$SLUG" "$USER"))"
    ;;
  delete)
    read -rp "Jira URL: " URL
    read -rp "Username: " USER
    SLUG="jira-$(echo "$URL" | sed 's|https\?://||;s|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//')"
    delete_credential "$SLUG" "$USER"
    ;;
  list)
    list_credentials
    ;;
  verify)
    read -rp "Jira URL: " URL
    read -rp "Username: " USER
    SLUG="jira-$(echo "$URL" | sed 's|https\?://||;s|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//')"
    verify_credential "$SLUG" "$USER"
    ;;
  *)
    echo "Unknown action: $ACTION. Use add|update|delete|list|verify."; exit 1 ;;
esac
