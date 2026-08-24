#!/usr/bin/env bash
# common/sh-check.sh — PostToolUse: bash syntax + shellcheck on .sh edits
# Claude Code passes hook input as JSON on stdin
# Copy to .claude/hooks/sh-check.sh in your repo
#
# Blocks with exit 2, which is the code Claude Code feeds back to the agent.
# An earlier version exited 1 on a syntax error (surfaced but did not block)
# and ran shellcheck under `|| true` (could never fail), so it reported as a
# gate while passing everything.
#
# Severity is --severity=error so the hook flags only what is unambiguously
# broken. Most existing repos carry warning-level diagnostics, and gating on
# those would block edits over pre-existing issues.
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
