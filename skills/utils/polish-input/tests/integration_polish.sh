#!/usr/bin/env bash
# Integration test for polish-input. Hits the real Anthropic API.
# Gated behind RUN_INTEGRATION=1 so CI doesn't burn tokens by default.
set -euo pipefail

if [[ "${RUN_INTEGRATION:-0}" != "1" ]]; then
  echo "SKIP: set RUN_INTEGRATION=1 to run integration tests"
  exit 0
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "SKIP: ANTHROPIC_API_KEY not set"
  exit 0
fi

if ! python3 -c "import anthropic" 2>/dev/null; then
  echo "SKIP: anthropic SDK not installed (pip install --user anthropic)"
  exit 0
fi

POLISH="$(cd "$(dirname "$0")/.." && pwd)/lib/polish.py"

run_case() {
  local input="$1" expect_keyword="$2"
  local out err
  out=$(mktemp); err=$(mktemp)
  echo -n "$input" | python3 "$POLISH" >"$out" 2>"$err"
  if [[ -n "$expect_keyword" ]] && ! grep -q "$expect_keyword" "$err"; then
    echo "FAIL: expected '$expect_keyword' in stderr for input: $input"
    echo "  stderr: $(cat "$err")"
    rm -f "$out" "$err"
    exit 1
  fi
  rm -f "$out" "$err"
  echo "OK: $input"
}

run_case "i want add login" "[polish]"
run_case "let surf" "[polish]"
# Already-fluent input: no [polish] line is acceptable.
run_case "Read the auth file." ""

echo "All integration cases passed."
