#!/usr/bin/env bash
# js/ts-fix.sh — PostToolUse: auto-format TS/JS/CSS with prettier
# Copy to .claude/hooks/ts-fix.sh in your repo
set -euo pipefail

input=$(cat)
file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{})
print(i.get('path') or i.get('file_path') or '')
" 2>/dev/null)

[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ "$file" =~ \.(ts|tsx|js|jsx|css)$ ]] || exit 0

APP_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PRETTIER="$APP_DIR/node_modules/.bin/prettier"

if [[ -f "$PRETTIER" ]]; then
  "$PRETTIER" --write --log-level=silent "$file" 2>/dev/null || true
fi
exit 0
