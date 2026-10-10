#!/usr/bin/env bash
# placeholder-guard.sh — PostToolUse: warn when an edit ADDS hardcoded IPs/credentials to YAML
# Diff-aware: only lines this change introduces are checked, so pre-existing
# committed values don't fire on every edit of the same file.
# Shared with the sibling repo — only the "repo config" block below may differ.
set -euo pipefail

# --- repo config --------------------------------------------------------------
YAML_SCOPE=""   # glob the file must match; empty = every YAML in the repo
# -------------------------------------------------------------------------------

input=$(cat)
file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{})
print(i.get('path') or i.get('file_path') or '')
" 2>/dev/null)

[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ "$file" != *.yaml && "$file" != *.yml ]] && exit 0
# shellcheck disable=SC2053  # intentional glob match
[[ -n "$YAML_SCOPE" && "$file" != $YAML_SCOPE ]] && exit 0

# collect only ADDED lines (untracked file → whole file), drop comments
if git ls-files --error-unmatch "$file" &>/dev/null; then
  added=$(git diff -U0 HEAD -- "$file" 2>/dev/null | grep '^+[^+]' | cut -c2- || true)
else
  added=$(cat "$file")
fi
added=$(echo "$added" | grep -vE '^[[:space:]]*#' || true)
[[ -z "$added" ]] && exit 0

WARN=0

if echo "$added" | grep -qE '\b[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b'; then
  echo "WARNING: this edit adds a hardcoded IP to $file" >&2
  echo "  Use <PLACEHOLDER_NAME> — real values go in Vault or Kustomize overlays." >&2
  WARN=1
fi

if echo "$added" | grep -qE '(password|secret|token|api.?key):[[:space:]]*[^$<{"'"'"'][^ ]{3,}'; then
  echo "WARNING: this edit adds a possible hardcoded credential to $file" >&2
  echo "  Use Vault/ExternalSecret — never commit real credentials." >&2
  WARN=1
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
