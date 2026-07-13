#!/usr/bin/env bash
# k8s/placeholder-guard.sh — PostToolUse: warn on hardcoded IPs/secrets in YAML
# Copy to .claude/hooks/placeholder-guard.sh in your repo
set -euo pipefail

input=$(cat)
file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{})
print(i.get('path') or i.get('file_path') or '')
" 2>/dev/null)

[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ "$file" != *.yaml && "$file" != *.yml ]] && exit 0

WARN=0

if grep -nE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$file" 2>/dev/null \
    | grep -v '^\s*#' | grep -q .; then
  echo "WARNING: possible hardcoded IP in $file" >&2
  echo "  Use <PLACEHOLDER_NAME> — real values go in Vault or Kustomize overlays." >&2
  WARN=1
fi

if grep -nE '(password|secret|token|api.?key):\s*[^$<{"'"'"'][^ ]{3,}' "$file" 2>/dev/null \
    | grep -v '^\s*#' | grep -q .; then
  echo "WARNING: possible hardcoded credential in $file" >&2
  echo "  Use Vault/ExternalSecret — never commit real credentials." >&2
  WARN=1
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
