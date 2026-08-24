#!/usr/bin/env bash
# python/py-check.sh — PostToolUse: syntax-check an edited *.py
# Claude Code passes hook input as JSON on stdin
# Copy to .claude/hooks/py-check.sh in your repo
#
# Uses ast.parse, NOT py_compile: py_compile writes __pycache__ next to every
# file it touches, which is the wrong side effect for a hook that fires on
# every edit. ast.parse raises the same SyntaxError and writes nothing.
#
# Syntax only, deliberately. Pair it with py-guard.sh (Stop) for linting: most
# existing repos carry lint findings, so gating an edit on them would block
# over pre-existing issues rather than the change at hand.
set -euo pipefail

input=$(cat)

# Fail open on unparseable stdin rather than blocking the edit.
file=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
i = d.get('tool_input', {}) or {}
print(i.get('file_path') or i.get('path') or '')
" 2>/dev/null)

[[ -z "$file" || "$file" != *.py || ! -f "$file" ]] && exit 0

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

exit 0
