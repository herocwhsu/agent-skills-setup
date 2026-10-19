#!/usr/bin/env bash
# common/verify-gate.sh — Stop hook: run the repo's verify commands (agent-harness.json)
# Copy to .claude/hooks/verify-gate.sh in your repo
# Runs when the turn changed a path matching RELEVANT_RE, measured against the
# upstream merge-base plus untracked files, like the other Stop guards. Blocks
# (exit 2) on the first failing command with its last lines. With the harness
# installed, each run is logged to <runtime>/telemetry/<repo>/verify-runs-YYYYMM.jsonl.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- repo config --------------------------------------------------------------
RELEVANT_RE='.'   # paths whose change needs verify; '.' = any change
# -------------------------------------------------------------------------------

changed_paths() {
  local re="$1" base
  base=$(git -C "$REPO_ROOT" merge-base '@{upstream}' HEAD 2>/dev/null || echo HEAD)
  {
    git -C "$REPO_ROOT" diff --name-only "$base" 2>/dev/null || true
    git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null || true
  } | grep -E "$re" | sort -u || true
}

hook_input=$(mktemp)
trap 'rm -f "$hook_input"' EXIT
[[ -t 0 ]] || cat > "$hook_input"

cd "$REPO_ROOT" || exit 0
[[ -f agent-harness.json ]] || { echo "  SKIP  verify: no agent-harness.json"; exit 0; }
if [[ -z "$(changed_paths "$RELEVANT_RE")" ]]; then
  echo "  SKIP  verify: turn changed nothing it covers"
  exit 0
fi

cmds=$(python3 -c '
import json,sys
for c in json.load(open("agent-harness.json")).get("verify", []):
    print(c)
' 2>/dev/null)
[[ -n "$cmds" ]] || { echo "  SKIP  verify: no verify commands in agent-harness.json"; exit 0; }

out_file=$(mktemp); results=$(mktemp)
trap 'rm -f "$out_file" "$results" "$hook_input"' EXIT
start=$(date +%s); failed=""
while IFS= read -r cmd; do
  t0=$(date +%s)
  bash -c "$cmd" > "$out_file" 2>&1 < /dev/null; rc=$?
  printf '%s\t%s\t%s\n' "$rc" "$(( $(date +%s) - t0 ))" "$cmd" >> "$results"
  if [[ $rc -ne 0 ]]; then failed="$cmd"; break; fi
done <<< "$cmds"
duration=$(( $(date +%s) - start ))

runtime="$HOME/.agent-skills-setup"
if [[ -f "$runtime/harness-version.json" ]]; then
  python3 - "$runtime" "$(basename "$REPO_ROOT")" "$(git rev-parse --short HEAD 2>/dev/null)" \
    "${failed:+fail}" "$duration" "$results" "$hook_input" <<'PY' || true
import datetime, json, os, sys
runtime, repo, commit, failed, duration, results, hook_input = sys.argv[1:8]
try:
    session = json.load(open(hook_input, encoding="utf-8")).get("session_id") or None
except (OSError, ValueError, AttributeError):
    session = None
commands = []
for line in open(results, encoding="utf-8"):
    rc, secs, cmd = line.rstrip("\n").split("\t", 2)
    commands.append({"cmd": cmd, "rc": int(rc), "duration_s": int(secs)})
now = datetime.datetime.now().astimezone()
row = {"ts": now.isoformat(timespec="seconds"), "repo": repo, "commit": commit or None,
       "result": "fail" if failed else "pass", "duration_s": int(duration), "commands": commands,
       "session_id": session if isinstance(session, str) else None}
d = os.path.join(runtime, "telemetry", repo)
os.makedirs(d, exist_ok=True)
with open(os.path.join(d, f"verify-runs-{now:%Y%m}.jsonl"), "a", encoding="utf-8") as f:
    f.write(json.dumps(row) + "\n")
PY
fi

if [[ -n "$failed" ]]; then
  rc=$(tail -1 "$results" | cut -f1)
  echo "verify failed: '$failed' (exit $rc) — last lines:" >&2
  tail -40 "$out_file" >&2
  exit 2
fi
echo "  OK    verify passed (${duration}s)"
exit 0
