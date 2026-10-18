#!/usr/bin/env bash
# global/global-hook.sh — the harness's global hooks, for every repo on this host
# install.sh copies it to <runtime>/hooks/, next to the hooks it runs, and wires it
# into each agent's user settings (config/global-hooks.json).
# Usage: global-hook.sh <claude|agy|codex> <edit|stop|start>
# The repo comes from the hook input, not the working directory: agy runs global
# hooks in ~/.gemini/config. A repo that wires a hook of the same name for this
# agent keeps its own, with its config block, and the global one is skipped.
set -uo pipefail

agent="${1:-}" event="${2:-}"
case "$agent:$event" in
  claude:edit|claude:stop|claude:start|agy:edit|agy:stop|codex:edit|codex:stop) ;;
  *) echo "global-hook.sh: usage: global-hook.sh <claude|agy|codex> <edit|stop|start>" >&2; exit 1 ;;
esac
case "$event" in
  edit)  hook=sh-check.sh ;;
  stop)  hook=secret-scan.sh ;;
  start) hook=preflight.sh ;;
esac
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
input=$(cat)

skip() {
  [[ "$agent" == agy ]] && echo "{}"
  exit 0
}

dir=$(printf '%s' "$input" | python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
i = d.get("tool_input") or {}
a = (d.get("toolCall") or {}).get("args") or {}
f = i.get("file_path") or i.get("path") or a.get("TargetFile") or a.get("AbsolutePath")
if isinstance(f, str) and os.path.isabs(f):
    print(os.path.dirname(f))
else:
    print(d.get("cwd") or (d.get("workspacePaths") or [""])[0])
' 2>/dev/null)
[[ -n "$dir" && -d "$dir" ]] || dir="$PWD"
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root="$dir"
cd "$root" || skip

# Only this agent's own repo settings: a repo that wires a hook for Claude alone
# must not turn the global one off for agy or codex.
case "$agent" in
  claude) own=(.claude/settings.json .claude/settings.local.json) ;;
  agy)    own=(.agents/hooks.json) ;;
  codex)  own=(.codex/hooks.json) ;;
esac
for f in "${own[@]}"; do
  grep -qsF "$hook" "$f" && skip
done
[[ "$event" == start && ! -f PROGRESS.md && ! -f agent-harness.json ]] && skip

if [[ "$agent" == claude ]]; then
  printf '%s' "$input" | bash "$here/$hook"
  exit $?
fi
printf '%s' "$input" | bash "$here/agent-hook.sh" "$agent" "$event" "$here/$hook"
