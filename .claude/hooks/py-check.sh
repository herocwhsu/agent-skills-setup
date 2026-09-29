#!/usr/bin/env bash
# py-check.sh — PostToolUse(Edit|Write|MultiEdit): syntax-check an edited *.py.
#
# Uses ast.parse, NOT py_compile: py_compile writes __pycache__ next to every
# file it touches, which is the wrong side effect for a hook that fires on
# every edit. ast.parse raises the same SyntaxError and writes nothing.
#
# Syntax only, deliberately. `ruff check` reports 74 findings under its default
# rules and `ruff format` would rewrite ~2400 lines, so linting or formatting
# here would block on, or churn, code unrelated to the current edit.
#
# Exit 2 blocks (Claude Code re-reads stderr and can self-correct), matching
# the other hooks in this directory; exit 0 allows.
set -euo pipefail

input=$(cat)

is_agy=0
if printf '%s' "$input" | python3 -c "import json, sys; d=json.load(sys.stdin); sys.exit(0 if 'toolCall' in d or 'conversationId' in d else 1)" 2>/dev/null; then
  is_agy=1
fi

# Fail open on unparseable JSON, matching precommit-sh-check.sh's posture.
file=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
i = d.get('tool_input', {}) or {}
args = d.get('toolCall', {}).get('args', {}) or {}
print(i.get('file_path') or i.get('path') or i.get('target_file') or args.get('TargetFile') or args.get('AbsolutePath') or '')
" 2>/dev/null)

if [[ -z "$file" || "$file" != *.py || ! -f "$file" ]]; then
  [[ "$is_agy" -eq 1 ]] && echo "{}"
  exit 0
fi

if ! out=$(python3 -c "
import ast, sys
p = sys.argv[1]
try:
    ast.parse(open(p, encoding='utf-8').read(), filename=p)
except SyntaxError as e:
    print(f'{e.msg} (line {e.lineno})')
    sys.exit(1)
" "$file" 2>&1); then
  {
    echo "Blocked: python syntax error in $file"
    printf '%s\n' "$out"
  } >&2
  exit 2
fi

[[ "$is_agy" -eq 1 ]] && echo "{}"
exit 0
