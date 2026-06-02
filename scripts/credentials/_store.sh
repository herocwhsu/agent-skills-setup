#!/usr/bin/env bash
# credentials/_store.sh — generic keychain CRUD with namespace prefix
# Source this file: source "$(dirname "$0")/_store.sh"
#
# All keychain entries are prefixed with "agent-skills-setup:" to avoid collisions.
# Passwords are NEVER exported to env vars — read from keychain at use-time only.
#
# Public API:
#   store_credential       <service-slug> <username> <password>
#   read_credential        <service-slug> <username>  → stdout: password
#   read_credential_inline <service-slug> <username>  → stdout: shell substitution string
#   delete_credential      <service-slug> <username>
#   list_credentials                                   → prints stored entries
#   verify_credential      <service-slug> <username>  → exits 1 if not found

readonly _KEYCHAIN_PREFIX="agent-skills-setup"

_svc_key() { echo "${_KEYCHAIN_PREFIX}:$1"; }

_os() {
  case "$(uname -s)" in
    Darwin)        echo "darwin" ;;
    Linux)
      if command -v secret-tool &>/dev/null; then
        echo "linux-gui"
      else
        echo "linux-file" # Fallback to file storage
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)             echo "unknown" ;;
  esac
}

readonly _FALLBACK_STORE="$HOME/.agent-skills-setup/credentials.json"

_ensure_fallback_dir() {
  mkdir -p "$(dirname "$_FALLBACK_STORE")"
  if [[ ! -f "$_FALLBACK_STORE" ]]; then
    echo "{}" > "$_FALLBACK_STORE"
    chmod 0600 "$_FALLBACK_STORE"
  fi
}

# ---------------------------------------------------------------------------
# store_credential <service-slug> <username> <password>
# ---------------------------------------------------------------------------
store_credential() {
  local svc; svc=$(_svc_key "$1")
  local user="$2" pass="$3"
  case "$(_os)" in
    darwin)
      security delete-generic-password -s "$svc" -a "$user" >/dev/null 2>&1 || true
      security add-generic-password -s "$svc" -a "$user" -w "$pass" 2>/dev/null
      ;;
    linux-gui)
      echo -n "$pass" | secret-tool store --label="$svc" service "$svc" username "$user"
      ;;
    linux-file)
      _ensure_fallback_dir
      # Use python to safely update the JSON file
      python3 -c "import json, os; p = os.path.expanduser('$_FALLBACK_STORE'); d = json.load(open(p)); d['$svc:$user'] = '$pass'; json.dump(d, open(p, 'w'), indent=2)"
      ;;
    linux-headless)
      echo "WARN: no keychain on headless Linux. Inject credential via CI secret." >&2
      return 1
      ;;
    windows)
      cmdkey /add:"$svc:$user" /user:"$user" /pass:"$pass" >nul 2>&1
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
    linux-file)
      if [[ -f "$_FALLBACK_STORE" ]]; then
        python3 -c "import json, os; p = os.path.expanduser('$_FALLBACK_STORE'); d = json.load(open(p)); print(d.get('$svc:$user', ''))"
      fi
      ;;
    linux-headless)
      echo "" ;;
    windows)
      powershell.exe -NoProfile -Command \
        "(Get-StoredCredential -Target '${svc}:${user}').GetNetworkCredential().Password" \
        2>/dev/null || true
      ;;
  esac
}

# ---------------------------------------------------------------------------
# read_credential_inline <service-slug> <username>
# Prints a shell command string that reads the credential at use-time.
# Embed in scripts as: PASS=$(read_credential_inline slug user)
# The returned string is safe to store in SKILL.md — it contains no secret.
# ---------------------------------------------------------------------------
read_credential_inline() {
  local svc; svc=$(_svc_key "$1")
  local user="$2"
  case "$(_os)" in
    darwin)
      echo "security find-generic-password -s '${svc}' -a '${user}' -w 2>/dev/null"
      ;;
    linux-gui)
      echo "secret-tool lookup service '${svc}' username '${user}' 2>/dev/null"
      ;;
    linux-headless)
      echo "echo \"\${CONFLUENCE_PASS:-}\"  # set via CI secret injection"
      ;;
    windows)
      echo "powershell.exe -NoProfile -Command \"(Get-StoredCredential -Target '${svc}:${user}').GetNetworkCredential().Password\""
      ;;
  esac
}

# ---------------------------------------------------------------------------
# verify_credential <service-slug> <username>
# Checks credential exists without printing it. Exits 1 if missing.
# ---------------------------------------------------------------------------
verify_credential() {
  local val
  val=$(read_credential "$1" "$2")
  if [[ -z "$val" ]]; then
    echo "  ✗ No credential found for $1 / $2" >&2
    return 1
  fi
  echo "  ✓ Credential found for $1 / $2 (value hidden)"
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
# list_credentials  → prints service:user lines (no passwords)
# ---------------------------------------------------------------------------
list_credentials() {
  echo "Stored credentials (prefix: ${_KEYCHAIN_PREFIX}:):"
  case "$(_os)" in
    darwin)
      local out
      out=$(security dump-keychain 2>/dev/null | python3 -c "
import sys, re
PREFIX = '${_KEYCHAIN_PREFIX}:'
for entry in sys.stdin.read().split('keychain:'):
    svce = re.search(r'\"svce\"<blob>=\"([^\"]+)\"', entry)
    acct = re.search(r'\"acct\"<blob>=\"([^\"]+)\"', entry)
    if svce and acct and svce.group(1).startswith(PREFIX):
        print('  ' + svce.group(1) + '  [' + acct.group(1) + ']')
")
      [ -n "$out" ] && echo "$out" || echo "  (none)"
      ;;
    linux-gui)
      secret-tool search service "" 2>/dev/null \
        | grep "${_KEYCHAIN_PREFIX}:" \
        || echo "  (none)"
      ;;
    linux-headless)
      echo "  (headless — credentials injected via CI, not stored locally)" ;;
    windows)
      cmdkey /list 2>/dev/null \
        | grep "${_KEYCHAIN_PREFIX}:" \
        || echo "  (none)"
      ;;
  esac
}
