#!/usr/bin/env bash
# sh-check.sh — PostToolUse(Edit|Write|MultiEdit): bash -n + shellcheck on an
# edited *.sh, giving edit-time feedback instead of waiting for the
# precommit-sh-check.sh gate at `git commit`.
#
# Severity is --severity=error deliberately: the repo is clean at error level
# but carries warning-level diagnostics, so gating on warnings would block
# on pre-existing issues unrelated to the current edit.
#
# Exit 2 blocks (Claude Code re-reads stderr and can self-correct), matching
# the other hooks in this directory; exit 0 allows.
set -euo pipefail

input=$(cat)

is_agy=0
if printf '%s' "$input" | python3 -c "import json, sys; d=json.load(sys.stdin); sys.exit(0 if 'toolCall' in d or 'conversationId' in d else 1)" 2>/dev/null; then
  is_agy=1
fi

file_list=$(printf '%s' "$input" | python3 -c "
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
i = d.get('tool_input', {}) or {}
args = d.get('toolCall', {}).get('args', {}) or {}
cmd = i.get('command') if isinstance(i.get('command'), str) else ''
# Codex edits through apply_patch: the paths exist only in the patch text,
# absolute or relative to the payload cwd, and one patch can touch many files.
if d.get('tool_name') == 'apply_patch' or cmd.startswith('*** Begin Patch'):
    base = d.get('cwd') or '.'
    for line in cmd.splitlines():
        for tag in ('*** Add File: ', '*** Update File: ', '*** Move to: '):
            if line.startswith(tag):
                print(os.path.join(base, line[len(tag):].strip()))
else:
    print(i.get('file_path') or i.get('path') or i.get('target_file') or args.get('TargetFile') or args.get('AbsolutePath') or '')
" 2>/dev/null)

files=()
while IFS= read -r f; do
  [[ -n "$f" ]] && files+=("$f")
done <<< "$file_list"

scratch=$(mktemp)
trap 'rm -f "$scratch"' EXIT

for file in ${files[@]+"${files[@]}"}; do
  [[ "$file" == *.sh && -f "$file" ]] || continue
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
done

[[ "$is_agy" -eq 1 ]] && echo "{}"
exit 0
