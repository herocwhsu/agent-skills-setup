#!/usr/bin/env bash
# Integration test for polish-input. Requires Java + language_tool_python.
# Skips with exit 0 if either is missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLISH="$SCRIPT_DIR/../lib/polish.py"

if ! command -v java &>/dev/null; then
  echo "SKIP: java not found"
  exit 0
fi
if ! python3 -c "import language_tool_python" 2>/dev/null; then
  echo "SKIP: language_tool_python not installed"
  exit 0
fi

OUT_FILE=$(mktemp)
ERR_FILE=$(mktemp)
trap 'rm -f "$OUT_FILE" "$ERR_FILE"' EXIT

echo "i want add login" | python3 "$POLISH" >"$OUT_FILE" 2>"$ERR_FILE"

# stdout must be the original (replace mode is not set).
if [[ "$(cat "$OUT_FILE")" != "i want add login" ]]; then
  echo "FAIL: stdout was $(cat "$OUT_FILE")"
  exit 1
fi

# stderr must contain the [polish] prefix.
if ! grep -q '^\[polish\]' "$ERR_FILE"; then
  echo "FAIL: stderr did not contain [polish] line:"
  cat "$ERR_FILE"
  exit 1
fi

echo "OK"
