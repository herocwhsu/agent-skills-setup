#!/usr/bin/env bash
# python/ruff-fix.sh — PostToolUse: auto-format Python with ruff
# Copy to .claude/hooks/ruff-fix.sh in your repo
set -euo pipefail

input=$(cat)
file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{})
print(i.get('path') or i.get('file_path') or '')
" 2>/dev/null)

[[ -z "$file" || "$file" != *.py || ! -f "$file" ]] && exit 0
command -v ruff &>/dev/null || exit 0

ruff format --quiet "$file" 2>/dev/null || true
ruff check --fix --quiet "$file" 2>/dev/null || true
exit 0
