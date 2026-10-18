#!/usr/bin/env bash
# js/ts-fix.sh — PostToolUse: auto-format TS/JS/CSS with prettier
# Copy to .claude/hooks/ts-fix.sh in your repo
# Uses the prettier of the APP_DIRS folder that holds the file.
set -euo pipefail

# --- repo config --------------------------------------------------------------
APP_DIRS=(".")   # frontend app folders, relative to the repo root; "." = the repo itself
# -------------------------------------------------------------------------------

input=$(cat)
file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{})
print(i.get('path') or i.get('file_path') or '')
" 2>/dev/null)

[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ "$file" =~ \.(ts|tsx|js|jsx|css)$ ]] || exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# git prints the physical path (/private/var/... on macOS); compare like with like
real="$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")"

for rel in "${APP_DIRS[@]}"; do
  if [[ "$rel" == "." ]]; then APP_DIR="$REPO_ROOT"; else APP_DIR="$REPO_ROOT/$rel"; fi
  [[ "$real" == "$APP_DIR"/* ]] || continue
  PRETTIER="$APP_DIR/node_modules/.bin/prettier"
  if [[ -f "$PRETTIER" ]]; then
    "$PRETTIER" --write --log-level=silent "$file" 2>/dev/null || true
  fi
  break
done
exit 0
