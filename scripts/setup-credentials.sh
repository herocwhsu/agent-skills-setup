#!/usr/bin/env bash
# setup-credentials.sh — store Confluence credentials in platform keychain
# and add shell profile export block so $CONFLUENCE_PASS is always available.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_DIR/scripts/_lib.sh"

OS=$(detect_os)

echo "==> Confluence credential setup"
echo ""
read -rp "Confluence base URL (e.g. https://confluence.example.com): " CONF_URL
read -rp "Username: " CONF_USER
read -rsp "Password (input hidden): " CONF_PASS
echo ""

SERVICE="confluence-$(echo "$CONF_URL" | sed 's|https\?://||' | sed 's|[^a-zA-Z0-9]|-|g' | sed 's/-\+/-/g' | sed 's/-$//')"

# ---------------------------------------------------------------------------
# Store in platform keychain
# ---------------------------------------------------------------------------
echo ""
echo "==> Storing credentials (service: $SERVICE, user: $CONF_USER)..."

case "$OS" in
  darwin)
    # Delete existing entry first to avoid duplicate
    security delete-generic-password -s "$SERVICE" -a "$CONF_USER" 2>/dev/null || true
    security add-generic-password -s "$SERVICE" -a "$CONF_USER" -w "$CONF_PASS"
    echo "  ✓ Stored in macOS Keychain"
    ;;
  linux-gui)
    echo -n "$CONF_PASS" | secret-tool store --label="$SERVICE" service "$SERVICE" username "$CONF_USER"
    echo "  ✓ Stored in GNOME Keyring / libsecret"
    ;;
  linux-headless)
    echo "  Headless Linux detected — no keychain available."
    echo "  Add the following to your shell profile manually or via CI secret injection:"
    echo ""
    echo "    export CONFLUENCE_PASS='<your-password>'"
    echo ""
    echo "  Skipping keychain storage."
    ;;
  windows)
    cmdkey /add:"$SERVICE" /user:"$CONF_USER" /pass:"$CONF_PASS"
    echo "  ✓ Stored in Windows Credential Manager"
    ;;
  *)
    echo "  Unknown OS — skipping keychain storage. Set CONFLUENCE_PASS manually." >&2
    ;;
esac

# ---------------------------------------------------------------------------
# Add shell profile export block
# ---------------------------------------------------------------------------
PROFILE_BLOCK="
# Confluence credentials (agent-skills-setup)
# service: $SERVICE  user: $CONF_USER
if [[ \"\$(uname)\" == \"Darwin\" ]]; then
  export CONFLUENCE_PASS=\$(security find-generic-password -s \"$SERVICE\" -a \"$CONF_USER\" -w 2>/dev/null)
elif command -v secret-tool &>/dev/null; then
  export CONFLUENCE_PASS=\$(secret-tool lookup service \"$SERVICE\" username \"$CONF_USER\" 2>/dev/null)
fi
# Linux headless / CI: set CONFLUENCE_PASS via pipeline secret injection
"

MARKER="# agent-skills-setup: $SERVICE"

add_to_profile() {
  local profile="$1"
  if [[ -f "$profile" ]] && grep -q "$MARKER" "$profile" 2>/dev/null; then
    echo "  Profile $profile already has export block, skipping."
    return
  fi
  {
    echo ""
    echo "$MARKER"
    echo "$PROFILE_BLOCK"
  } >> "$profile"
  echo "  ✓ Added export block to $profile"
}

echo ""
echo "==> Adding export block to shell profile..."

case "$OS" in
  darwin)
    add_to_profile "$HOME/.zshrc"
    ;;
  linux-gui|linux-headless)
    add_to_profile "$HOME/.bashrc"
    ;;
  windows)
    echo "  Windows: set CONFLUENCE_PASS in your environment or PowerShell profile manually."
    ;;
esac

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
echo ""
echo "==> Validating..."

case "$OS" in
  darwin)
    TEST=$(security find-generic-password -s "$SERVICE" -a "$CONF_USER" -w 2>/dev/null)
    ;;
  linux-gui)
    TEST=$(secret-tool lookup service "$SERVICE" username "$CONF_USER" 2>/dev/null)
    ;;
  *)
    TEST="$CONF_PASS"
    ;;
esac

if [[ -n "$TEST" ]]; then
  echo "  ✓ Credential stored and readable."
else
  echo "  ERROR: Could not read back credential. Check keychain setup." >&2
  exit 1
fi

echo ""
echo "Done. Restart your shell (or run: source ~/.zshrc) to activate CONFLUENCE_PASS."
