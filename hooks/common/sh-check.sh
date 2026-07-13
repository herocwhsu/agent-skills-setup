#!/usr/bin/env bash
# common/sh-check.sh — PostToolUse: bash syntax + shellcheck on .sh edits
# Claude Code passes hook input as JSON on stdin
# Copy to .claude/hooks/sh-check.sh in your repo
set -euo pipefail

input=$(cat)
file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{})
print(i.get('path') or i.get('file_path') or '')
" 2>/dev/null)

[[ -z "$file" || "$file" != *.sh || ! -f "$file" ]] && exit 0

bash -n "$file" 2>&1 || { echo "ERROR: bash syntax error in $file" >&2; exit 1; }
if command -v shellcheck &>/dev/null; then
  shellcheck --severity=warning "$file" 2>/dev/null || true
fi
exit 0
