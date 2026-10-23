#!/usr/bin/env bash
# common/preflight.sh — session start: harness checks and a short state brief
# Copy to .claude/hooks/preflight.sh in your repo
# Claude runs it as a SessionStart hook (its stdout joins the context); other
# agents run it as the first startup step in AGENTS.md. It never blocks: every
# finding is a warning, and it always exits 0. The brief replaces reading
# PROGRESS.md in full; open that file only when the brief is not enough.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" && in_repo=1 || { in_repo=0; REPO_ROOT="$(pwd)"; }
cd "$REPO_ROOT" || exit 0

echo "== preflight (agent-harness.json) =="
if [[ $in_repo -eq 0 && -f "$HOME/.agent-skills-setup/target-repos.txt" ]]; then
  below=$(awk -v p="$REPO_ROOT/" 'index($0, p) == 1' "$HOME/.agent-skills-setup/target-repos.txt")
  if [[ -n "$below" ]]; then
    echo "  WARN started above registered repos, so their hooks do not load; start the session inside one:"
    while IFS= read -r line; do echo "    $line"; done <<< "$below"
  fi
fi
src=$(python3 -c "
import json,sys
print(json.load(open(sys.argv[1])).get('source_dir') or '')
" "$HOME/.agent-skills-setup/harness-version.json" 2>/dev/null) || src=""
if [[ ! -f agent-harness.json ]]; then
  echo "  no agent-harness.json in this repo"
elif [[ -z "$src" || ! -f "$src/scripts/harness_adapter.py" ]]; then
  echo "  harness not installed on this host; version and drift not checked"
else
  python3 "$src/scripts/harness_adapter.py" check "$REPO_ROOT" \
    --templates "$src/templates/hooks" 2>&1 | sed 's/^ *OK  */  /; s/^ *FAIL */  WARN /'
  if ! out=$(python3 "$src/scripts/harness_adapter.py" drift "$REPO_ROOT" --templates "$src/templates/hooks" 2>&1); then
    while IFS= read -r line; do echo "  WARN $line"; done <<< "$out"
  else
    echo "  hook drift: none"
  fi
fi

echo "== state brief (PROGRESS.md) =="
if [[ ! -f PROGRESS.md ]]; then
  echo "  no PROGRESS.md"
  exit 0
fi
python3 - PROGRESS.md <<'PY' || true
import re, sys
caps = {"current state": 4, "in flight": 8, "next": 5, "standing decisions": 6}
items = {k: [] for k in caps}
section = None
joining = False  # the last line opened an item that a wrapped line may continue
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    m = re.match(r"^##\s+(.*?)\s*$", line)
    if m:
        name = m.group(1).lower()
        section = name if name in caps else None
        joining = False
        continue
    if section is None or line.startswith("#"):
        continue
    if not line.strip():
        joining = False
    elif re.match(r"^(?:[-*]|\d+\.)\s+\S", line):
        items[section].append(line.strip())
        joining = True
    elif line[0].isspace():
        # a wrapped line continues its item; a nested list item and what follows it do not
        if re.match(r"^\s+(?:[-*]|\d+\.)\s+\S", line):
            joining = False
        elif joining:
            items[section][-1] += " " + line.strip()
    elif joining and items[section]:
        items[section][-1] += " " + line.strip()
    else:
        items[section].append(line.strip())
        joining = True
for name, cap in caps.items():
    found = items[name]
    title = name[0].upper() + name[1:]
    if not found:
        print(f"{title}: (none)")
        continue
    print(f"{title}:")
    for line in found[:cap]:
        line = " ".join(line.split())
        print("  " + (line if len(line) <= 160 else line[:159] + "…"))
    if len(found) > cap:
        print(f"  (+{len(found) - cap} more in PROGRESS.md)")
PY
echo "(Open PROGRESS.md in full only when this brief is not enough.)"
exit 0
