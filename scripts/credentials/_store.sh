#!/usr/bin/env bash
# credentials/_store.sh — generic keychain CRUD with namespace prefix
# Source this file: source "$(dirname "$0")/_store.sh"
#
# All keychain entries are prefixed with "agent-skills:" to avoid collisions
# with system, browser, or other app entries.
#
# Public API:
#   store_credential  <service-slug> <username> <password>
#   read_credential   <service-slug> <username>           → prints password
#   delete_credential <service-slug> <username>
#   list_credentials                                       → prints "service:user" lines
#   add_profile_export   <service-slug> <username> <env-var>
#   remove_profile_export <service-slug>

readonly _KEYCHAIN_PREFIX="agent-skills"

# Build namespaced keychain key
_svc_key() { echo "${_KEYCHAIN_PREFIX}:$1"; }

# Detect OS (inline, no _lib.sh dependency)
_os() {
  case "$(uname -s)" in
    Darwin)        echo "darwin" ;;
    Linux)
      command -v secret-tool &>/dev/null && echo "linux-gui" || echo "linux-headless" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)             echo "unknown" ;;
  esac
}

# ---------------------------------------------------------------------------
# store_credential <service-slug> <username> <password>
# ---------------------------------------------------------------------------
store_credential() {
  local svc; svc=$(_svc_key "$1")
  local user="$2" pass="$3"
  case "$(_os)" in
    darwin)
      security delete-generic-password -s "$svc" -a "$user" 2>/dev/null || true
      security add-generic-password -s "$svc" -a "$user" -w "$pass"
      ;;
    linux-gui)
      echo -n "$pass" | secret-tool store --label="$svc" service "$svc" username "$user"
      ;;
    linux-headless)
      echo "WARN: no keychain on headless Linux. Set ${3:-PASSWORD} env var manually." >&2
      return 1
      ;;
    windows)
      cmdkey /add:"$svc:$user" /user:"$user" /pass:"$pass"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# read_credential <service-slug> <username>  → stdout: password (empty = not found)
# ---------------------------------------------------------------------------
read_credential() {
  local svc; svc=$(_svc_key "$1")
  local user="$2"
  case "$(_os)" in
    darwin)
      security find-generic-password -s "$svc" -a "$user" -w 2>/dev/null || true
      ;;
    linux-gui)
      secret-tool lookup service "$svc" username "$user" 2>/dev/null || true
      ;;
    linux-headless)
      echo "" ;;
    windows)
      # PowerShell read — prints password or empty
      powershell.exe -NoProfile -Command \
        "(Get-StoredCredential -Target '${svc}:${user}').GetNetworkCredential().Password" \
        2>/dev/null || true
      ;;
  esac
}

# ---------------------------------------------------------------------------
# delete_credential <service-slug> <username>
# ---------------------------------------------------------------------------
delete_credential() {
  local svc; svc=$(_svc_key "$1")
  local user="$2"
  case "$(_os)" in
    darwin)
      security delete-generic-password -s "$svc" -a "$user" 2>/dev/null \
        && echo "  ✓ deleted from macOS Keychain" \
        || echo "  (not found in keychain)"
      ;;
    linux-gui)
      secret-tool clear service "$svc" username "$user" 2>/dev/null \
        && echo "  ✓ deleted from libsecret" \
        || echo "  (not found)"
      ;;
    linux-headless)
      echo "  Nothing to delete (headless — no keychain)." ;;
    windows)
      cmdkey /delete:"${svc}:${user}" 2>/dev/null \
        && echo "  ✓ deleted from Windows Credential Manager" \
        || echo "  (not found)"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# list_credentials  → prints "agent-skills:<service>  <user>" lines
# ---------------------------------------------------------------------------
list_credentials() {
  echo "Stored credentials (prefix: ${_KEYCHAIN_PREFIX}:):"
  case "$(_os)" in
    darwin)
      security dump-keychain 2>/dev/null \
        | grep -A2 "\"svce\"" \
        | awk '/"svce"/{svc=$0} /"acct"/{print svc, $0}' \
        | grep "${_KEYCHAIN_PREFIX}:" \
        | sed 's/.*<blob>="//;s/".*//' \
        || echo "  (none)"
      ;;
    linux-gui)
      secret-tool search service "" 2>/dev/null \
        | grep "${_KEYCHAIN_PREFIX}:" \
        || echo "  (none)"
      ;;
    linux-headless)
      echo "  (headless — check shell profile for exported vars)" ;;
    windows)
      cmdkey /list 2>/dev/null \
        | grep "${_KEYCHAIN_PREFIX}:" \
        || echo "  (none)"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# add_profile_export <service-slug> <username> <env-var>
# Appends a keychain-backed export block to the shell profile (idempotent).
# ---------------------------------------------------------------------------
add_profile_export() {
  local svc_slug="$1" user="$2" var="$3"
  local svc; svc=$(_svc_key "$svc_slug")
  local marker="# agent-skills:${svc_slug}"
  local profile
  case "$(_os)" in
    darwin)        profile="$HOME/.zshrc" ;;
    linux-*)       profile="$HOME/.bashrc" ;;
    windows)       echo "  Windows: set $var manually in your environment."; return ;;
    *)             echo "  Unknown OS: set $var manually."; return ;;
  esac

  if grep -qF "$marker" "$profile" 2>/dev/null; then
    echo "  Profile already has export for $var, skipping."
    return
  fi

  cat >> "$profile" <<EOF

${marker}
if [[ "\$(uname)" == "Darwin" ]]; then
  export ${var}=\$(security find-generic-password -s "${svc}" -a "${user}" -w 2>/dev/null)
elif command -v secret-tool &>/dev/null; then
  export ${var}=\$(secret-tool lookup service "${svc}" username "${user}" 2>/dev/null)
fi
EOF
  echo "  ✓ Added export ${var} to $profile"
}

# ---------------------------------------------------------------------------
# remove_profile_export <service-slug>
# Removes the export block added by add_profile_export (idempotent).
# ---------------------------------------------------------------------------
remove_profile_export() {
  local svc_slug="$1"
  local marker="# agent-skills:${svc_slug}"
  local profile
  case "$(_os)" in
    darwin)  profile="$HOME/.zshrc" ;;
    linux-*) profile="$HOME/.bashrc" ;;
    *)       return ;;
  esac

  if ! grep -qF "$marker" "$profile" 2>/dev/null; then
    echo "  No profile export found for $svc_slug, skipping."
    return
  fi

  # Remove the marker line + the 5 lines that follow it (the export block)
  sed -i.bak "/$(echo "$marker" | sed 's/[\/&]/\\&/g')/,+5d" "$profile"
  rm -f "${profile}.bak"
  echo "  ✓ Removed export block from $profile"
}
