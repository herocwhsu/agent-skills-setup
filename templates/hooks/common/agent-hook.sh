#!/usr/bin/env bash
# common/agent-hook.sh — run a shared hook (written for Claude) under agy or codex
# Copy to .claude/hooks/agent-hook.sh in your repo
# Usage: agent-hook.sh <agy|codex> <edit|stop> <hook.sh>
# The shared hooks read Claude's input ({"tool_input":{"file_path":...}}) and block
# with exit 2 + stderr. This turns the agent's input into that shape, one call per
# edited file, and the hook's result into the agent's answer:
#   agy    edit: {} on success, exit 2 + stderr on failure
#          stop: {} on success, {"decision":"continue","reason":...} on failure
#   codex  same as Claude: exit 2 + stderr blocks; apply_patch names its files as
#          "*** Add File: <path>" / "*** Update File: <path>" lines
set -uo pipefail

agent="${1:-}" event="${2:-}" hook="${3:-}"
case "$agent:$event" in
  agy:edit|agy:stop|codex:edit|codex:stop) ;;
  *) echo "agent-hook.sh: usage: agent-hook.sh <agy|codex> <edit|stop> <hook.sh>" >&2; exit 1 ;;
esac
input=$(cat)

if [[ "$event" == stop ]]; then
  out=$(printf '{}' | bash "$hook" 2>&1); rc=$?
  if [[ "$agent" == agy ]]; then
    if [[ $rc -eq 2 ]]; then
      python3 -c 'import json,sys; print(json.dumps({"decision": "continue", "reason": sys.argv[1] + " blocked:\n" + sys.argv[2]}))' "$(basename "$hook")" "$out"
    else
      echo "{}"
    fi
    exit 0
  fi
  [[ -n "$out" ]] && echo "$out" >&2
  exit "$rc"
fi

files=$(printf '%s' "$input" | python3 -c '
import json, os, re, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
# codex names patched files relative to its session folder, which this script
# (run from the repo root) may not be in; the hooks match on absolute paths.
base = d.get("cwd") or os.getcwd()
i = d.get("tool_input") or {}
a = (d.get("toolCall") or {}).get("args") or {}
direct = i.get("file_path") or i.get("path") or a.get("TargetFile") or a.get("AbsolutePath")
if isinstance(direct, str) and direct:
    print(os.path.join(base, direct))
    sys.exit(0)
seen = []
def walk(v):
    if isinstance(v, str):
        for m in re.finditer(r"^\*\*\* (?:Add|Update) File: (.+?)\s*$", v, re.M):
            if m.group(1) not in seen:
                seen.append(m.group(1))
    elif isinstance(v, dict):
        for x in v.values(): walk(x)
    elif isinstance(v, list):
        for x in v: walk(x)
walk(i)
print("\n".join(os.path.join(base, p) for p in seen))
')

errors="" blocked=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_input": {"file_path": sys.argv[1]}}))' "$f")
  out=$(printf '%s' "$payload" | bash "$hook" 2>&1); rc=$?
  # Only exit 2 blocks, as in Claude; any other failure is reported, not enforced.
  if [[ $rc -eq 2 ]]; then
    blocked=1
    errors+="$out"$'\n'
  elif [[ $rc -ne 0 ]]; then
    echo "$(basename "$hook") exited $rc (not blocking): $out" >&2
  fi
done <<< "$files"

if [[ $blocked -eq 1 ]]; then
  printf '%s' "$errors" >&2
  exit 2
fi
[[ "$agent" == agy ]] && echo "{}"
exit 0
