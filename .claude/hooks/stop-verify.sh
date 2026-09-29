#!/usr/bin/env bash
# stop-verify.sh — Stop hook wrapper running harness-verify across agents.
#
# AGY Stop hook contract: returns `{"decision": "continue", "reason": ...}`
# on stdout if verification fails (exit 0), or `{}` if clean (exit 0).
#
# Claude / Codex Stop hook contract: exits 2 with error on stderr to block
# stopping when verification fails; exits 0 when clean.
set -euo pipefail

input=$(cat)

is_agy=0
if printf '%s' "$input" | python3 -c "import json, sys; d=json.load(sys.stdin); sys.exit(0 if any(k in d for k in ('executionNum', 'terminationReason', 'toolCall', 'conversationId')) else 1)" 2>/dev/null; then
  is_agy=1
fi

if git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_DIR="$(git rev-parse --show-toplevel)"
else
  REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
  [[ "$(basename "$REPO_DIR")" == ".agents" ]] && REPO_DIR="$(cd "$REPO_DIR/.." && pwd)"
fi

out=""
status=0
out=$(bash "$REPO_DIR/scripts/harness-verify.sh" 2>&1) || status=$?

if [[ $status -eq 0 ]]; then
  [[ "$is_agy" -eq 1 ]] && echo "{}"
  exit 0
fi

if [[ "$is_agy" -eq 1 ]]; then
  python3 -c "import json, sys; print(json.dumps({'decision': 'continue', 'reason': 'harness-verify failed:\n' + sys.argv[1]}))" "$out"
  exit 0
fi

printf '%s\n' "$out" >&2
exit 2
