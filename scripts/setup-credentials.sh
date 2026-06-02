#!/usr/bin/env bash
# setup-credentials.sh — manage credentials for all services
# Usage: bash setup-credentials.sh [service] [action]
#   service: confluence | jira | apidog
#   action:  add | update | delete | list | verify
set -euo pipefail

CREDS_DIR="$(cd "$(dirname "$0")/credentials" && pwd)"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
case "${1:-}" in
  -h|--help|help)
    cat <<EOF
Usage: $(basename "$0") [service] [action]

Services: confluence | jira | apidog | anthropic | gemini
Actions:  add | update | delete | list | verify

Examples:
  $(basename "$0") jira add        # interactive add
  $(basename "$0") confluence list # list stored credentials
  $(basename "$0")                 # interactive picker

With no arguments, prompts for service and action.
EOF
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Select service
# ---------------------------------------------------------------------------
SERVICE="${1:-}"
if [[ -z "$SERVICE" ]]; then
  echo "Which service?"
  echo "  1) Confluence"
  echo "  2) Jira"
  echo "  3) Apidog"
  echo "  4) Anthropic (for polish-input)"
  echo "  5) Gemini (for polish-input)"
  read -rp "Choice [1-5]: " choice
  case "$choice" in
    1) SERVICE="confluence" ;;
    2) SERVICE="jira" ;;
    3) SERVICE="apidog" ;;
    4) SERVICE="anthropic" ;;
    5) SERVICE="gemini" ;;
    *) echo "Invalid choice."; exit 1 ;;
  esac
fi

# ---------------------------------------------------------------------------
# Select action
# ---------------------------------------------------------------------------
ACTION="${2:-}"
if [[ -z "$ACTION" ]]; then
  echo ""
  echo "Action for $SERVICE?"
  echo "  1) add / update"
  echo "  2) delete"
  echo "  3) list all stored"
  read -rp "Choice [1-3]: " choice
  case "$choice" in
    1) ACTION="add" ;;
    2) ACTION="delete" ;;
    3) ACTION="list" ;;
    *) echo "Invalid choice."; exit 1 ;;
  esac
fi

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
SCRIPT="$CREDS_DIR/${SERVICE}.sh"
if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: No credential handler found for '$SERVICE' ($SCRIPT)." >&2
  exit 1
fi

bash "$SCRIPT" "$ACTION"
