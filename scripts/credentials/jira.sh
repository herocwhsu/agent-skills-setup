#!/usr/bin/env bash
# credentials/jira.sh — manage Jira credentials
# Usage: bash jira.sh <add|update|delete|list>
source "$(dirname "$0")/_store.sh"

ACTION="${1:-}"
if [[ -z "$ACTION" ]]; then
  echo "Usage: $0 <add|update|delete|list>"; exit 1
fi

case "$ACTION" in
  add|update)
    read -rp  "Jira URL (e.g. https://jira.example.com): " URL
    read -rp  "Username: " USER
    read -rsp "Password / API token (hidden): " PASS; echo
    SLUG="jira-$(echo "$URL" | sed 's|https\?://||;s|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//')"
    store_credential "$SLUG" "$USER" "$PASS"
    add_profile_export "$SLUG" "$USER" "JIRA_PASS"
    echo "  ✓ Jira credentials saved (env: JIRA_PASS)"
    ;;
  delete)
    read -rp "Jira URL: " URL
    read -rp "Username: " USER
    SLUG="jira-$(echo "$URL" | sed 's|https\?://||;s|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//')"
    delete_credential "$SLUG" "$USER"
    remove_profile_export "$SLUG"
    ;;
  list)
    list_credentials
    ;;
  *)
    echo "Unknown action: $ACTION. Use add|update|delete|list."; exit 1 ;;
esac
