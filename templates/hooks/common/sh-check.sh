#!/usr/bin/env bash
# sh-check.sh — PostToolUse: bash syntax + shellcheck on .sh edits
set -euo pipefail

input=$(cat)

is_agy=0
if printf '%s' "$input" | python3 -c "import json, sys; d=json.load(sys.stdin); sys.exit(0 if 'toolCall' in d or 'conversationId' in d else 1)" 2>/dev/null; then
  is_agy=1
fi

file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{}) or {}
a=d.get('toolCall',{}).get('args',{}) or {}
print(i.get('path') or i.get('file_path') or i.get('target_file') or a.get('TargetFile') or a.get('AbsolutePath') or '')
" 2>/dev/null)

if [[ -z "$file" || "$file" != *.sh || ! -f "$file" ]]; then
  [[ "$is_agy" -eq 1 ]] && echo "{}"
  exit 0
fi

if ! err=$(bash -n "$file" 2>&1); then
  echo "ERROR: bash syntax error in $file" >&2
  echo "$err" >&2
  exit 2
fi
if command -v shellcheck &>/dev/null; then
  # Must match CI exactly. This ran at --severity=warning until 2026-08-20,
  # strictly weaker than the pre-commit hook in CI, which runs at default
  # severity where style- and info-level findings count. Every such finding
  # therefore passed locally and failed the build -- the gate leaving its job
  # to the net. `-x` follows the `# shellcheck source=` directives already in
  # the tree; without it every sourcing script reports SC1091.
  if ! out=$(shellcheck -x "$file" 2>&1); then
    echo "shellcheck findings in $file:" >&2
    echo "$out" | head -30 >&2
    exit 2
  fi
fi
[[ "$is_agy" -eq 1 ]] && echo "{}"
exit 0
