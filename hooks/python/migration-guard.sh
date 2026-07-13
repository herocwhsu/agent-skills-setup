#!/usr/bin/env bash
# python/migration-guard.sh — PostToolUse: warn when modifying existing migration
# Copy to .claude/hooks/migration-guard.sh in your repo
set -euo pipefail

input=$(cat)
file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{})
print(i.get('path') or i.get('file_path') or '')
" 2>/dev/null)

[[ -z "$file" || "$file" != *.sql || ! -f "$file" ]] && exit 0

if git ls-files --error-unmatch "$file" &>/dev/null 2>&1; then
  echo "WARNING: modifying committed migration: $file" >&2
  echo "  Migrations are append-only. Create a new numbered file instead." >&2
  exit 2
fi
exit 0
