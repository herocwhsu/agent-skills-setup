#!/usr/bin/env bash
# sh-check.sh — PostToolUse(Edit|Write|MultiEdit): bash -n + shellcheck on an
# edited *.sh, giving edit-time feedback instead of waiting for the
# precommit-sh-check.sh gate at `git commit`.
#
# Severity is --severity=error deliberately: the repo is clean at error level
# but carries 17 warning-level diagnostics, so gating on warnings would block
# on pre-existing issues unrelated to the current edit.
#
# Exit 2 blocks (Claude Code re-reads stderr and can self-correct), matching
# the other hooks in this directory; exit 0 allows.
set -euo pipefail

input=$(cat)

# Fail open on unparseable JSON, matching precommit-sh-check.sh's posture.
file=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
i = d.get('tool_input', {}) or {}
print(i.get('file_path') or i.get('path') or '')
" 2>/dev/null)

[[ -z "$file" || "$file" != *.sh || ! -f "$file" ]] && exit 0

scratch=$(mktemp)
trap 'rm -f "$scratch"' EXIT

if ! bash -n "$file" 2>"$scratch"; then
  {
    echo "Blocked: bash syntax error in $file"
    cat "$scratch"
  } >&2
  exit 2
fi

if command -v shellcheck >/dev/null 2>&1; then
  if ! shellcheck --severity=error "$file" >"$scratch" 2>&1; then
    {
      echo "Blocked: shellcheck error in $file"
      cat "$scratch"
    } >&2
    exit 2
  fi
fi

exit 0
