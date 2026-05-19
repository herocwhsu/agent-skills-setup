#!/usr/bin/env bash
# lib.sh — runtime helpers for agent-skills-setup
# Installed at ~/.agent-skills-setup/lib.sh by install.sh.
# Source this from a SKILL.md:
#   source ~/.agent-skills-setup/lib.sh

# ---------------------------------------------------------------------------
# slugify_url <url>
#   Convert any URL to a deterministic slug suitable for keychain service IDs.
#   Portable across BSD sed (macOS) and GNU sed.
#
#   slugify_url https://example-org.atlassian.net
#   → https---example-atlassian-net
# ---------------------------------------------------------------------------
slugify_url() {
  echo "$1" | sed 's|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//'
}

# ---------------------------------------------------------------------------
# service_slug <prefix> <url>
#   Compose a service-prefixed slug.
#
#   service_slug jira https://example-org.atlassian.net
#   → jira-https---example-atlassian-net
# ---------------------------------------------------------------------------
service_slug() {
  echo "$1-$(slugify_url "$2")"
}

# ---------------------------------------------------------------------------
# find_html2md
#   Echo absolute path to html2md.py from whichever agent skills dir has it.
#   Returns 1 with stderr message if not found.
# ---------------------------------------------------------------------------
find_html2md() {
  local d
  for d in "$HOME/.kiro/skills" "$HOME/.claude/skills" "$HOME/.copilot/skills" "$HOME/.codex/skills"; do
    if [[ -f "$d/fetch-page-to-markdown/html2md.py" ]]; then
      echo "$d/fetch-page-to-markdown/html2md.py"
      return 0
    fi
  done
  echo "ERROR: html2md.py not found in any agent skills directory." >&2
  echo "  Run: bash scripts/install.sh" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Source _store.sh from the same directory (installed alongside lib.sh).
# Provides: store_credential, read_credential, verify_credential, list_credentials.
# ---------------------------------------------------------------------------
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$_LIB_DIR/_store.sh" ]]; then
  # shellcheck source=/dev/null
  source "$_LIB_DIR/_store.sh"
fi

# ---------------------------------------------------------------------------
# load_config
#   Source ~/.agent-skills-setup/config.sh into the current shell.
#   Print a clear hint and return 1 if missing.
# ---------------------------------------------------------------------------
load_config() {
  local config="$HOME/.agent-skills-setup/config.sh"
  if [[ ! -f "$config" ]]; then
    echo "ERROR: $config not found." >&2
    echo "  Run: bash scripts/setup-credentials.sh <service> add" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$config"
}

# ---------------------------------------------------------------------------
# read_secret <slug> <user>
#   Echo the secret to stdout. Empty string if missing. Never logs.
# ---------------------------------------------------------------------------
read_secret() {
  read_credential "$1" "$2"
}

# ---------------------------------------------------------------------------
# require_secret <slug> <user> [hint]
#   Echo secret to stdout. If missing, print hint to stderr and return 1.
# ---------------------------------------------------------------------------
require_secret() {
  local slug="$1" user="$2" hint="${3:-bash scripts/setup-credentials.sh}"
  local pass
  pass=$(read_credential "$slug" "$user")
  if [[ -z "$pass" ]]; then
    echo "ERROR: credential not found at $slug for $user" >&2
    echo "  Run: $hint" >&2
    return 1
  fi
  echo "$pass"
}

# ---------------------------------------------------------------------------
# migrate_keychain
#   Rename keychain entries from agent-skills:* to agent-skills-setup:*.
#   Idempotent: no-op and silent if all entries already use new prefix.
#   Safe: only deletes old entry after new entry write succeeds.
# ---------------------------------------------------------------------------
migrate_keychain() {
  local count=0 os
  os=$(uname -s)

  case "$os" in
    Darwin)
      local entries
      entries=$(security dump-keychain 2>/dev/null | python3 -c "
import sys, re
out = []
for entry in sys.stdin.read().split('keychain:'):
    s = re.search(r'\"svce\"<blob>=\"(agent-skills:[^\"]+)\"', entry)
    a = re.search(r'\"acct\"<blob>=\"([^\"]+)\"', entry)
    if s and a:
        out.append(s.group(1) + '\t' + a.group(1))
print('\n'.join(out))
" 2>/dev/null)

      while IFS=$'\t' read -r svc user; do
        [[ -z "$svc" ]] && continue
        local newsvc="agent-skills-setup:${svc#agent-skills:}"
        local pass
        pass=$(security find-generic-password -s "$svc" -a "$user" -w 2>/dev/null) || continue
        if security add-generic-password -s "$newsvc" -a "$user" -w "$pass" 2>/dev/null; then
          security delete-generic-password -s "$svc" -a "$user" 2>/dev/null
          count=$((count + 1))
        fi
      done <<< "$entries"
      ;;
    Linux)
      # secret-tool has no enumerate-by-prefix; Linux users re-add credentials manually.
      :
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # Windows migration via cmdkey list parsing — best-effort.
      while IFS= read -r line; do
        local target
        target=$(echo "$line" | sed -n 's/.*Target: \(agent-skills:[^ ]*\).*/\1/p')
        [[ -z "$target" ]] && continue
        # Re-prompt is the safest cross-version path; log a hint.
        echo "  → Windows migration needed for $target — run setup-credentials again." >&2
      done < <(cmdkey /list 2>/dev/null)
      ;;
  esac

  if [[ $count -gt 0 ]]; then
    echo "  ✓ migrated $count keychain entries: agent-skills: → agent-skills-setup:"
  fi
}
