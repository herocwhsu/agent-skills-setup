#!/usr/bin/env bash
# common/harness-drift.sh — PostToolUse: a shared hook copy must match its template
# Copy to .claude/hooks/harness-drift.sh in your repo
# A hook listed as a template in agent-harness.json may differ from
# agent-skills-setup/templates/hooks only inside its repo config block. Exit 2
# (message on stderr) when an edit changes anything else, so the fix goes into
# the template instead. The harness is found through harness-version.json; on a
# host without it (a clone on a server) this does nothing.
set -euo pipefail

input=$(cat)
file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{}) or {}
a=d.get('toolCall',{}).get('args',{}) or {}
print(i.get('path') or i.get('file_path') or a.get('TargetFile') or a.get('AbsolutePath') or '')
" 2>/dev/null)
[[ -n "$file" && "$file" == */.claude/hooks/* && -f "$file" ]] || exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[[ -f "$REPO_ROOT/agent-harness.json" ]] || exit 0
src=$(python3 -c "
import json,sys
print(json.load(open(sys.argv[1])).get('source_dir') or '')
" "$HOME/.agent-skills-setup/harness-version.json" 2>/dev/null) || exit 0
[[ -n "$src" && -f "$src/scripts/harness_adapter.py" ]] || exit 0

if ! out=$(python3 "$src/scripts/harness_adapter.py" drift "$REPO_ROOT" \
             --templates "$src/templates/hooks" --file "$file" 2>&1); then
  echo "WARNING: this hook is a harness copy; only its repo config block may differ:" >&2
  while IFS= read -r line; do echo "  $line" >&2; done <<< "$out"
  echo "  Make the change in $src/templates/hooks, then sync it here." >&2
  exit 2
fi
exit 0
