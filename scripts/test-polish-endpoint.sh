#!/usr/bin/env bash
# Smoke-test the LLM polish endpoint Handy will use.
# Usage: scripts/test-polish-endpoint.sh [base_url]
# Requires POLISH_API_KEY (or ANTHROPIC_API_KEY) in the environment.
set -euo pipefail

BASE_URL="${1:-https://api.anthropic.com/v1}"
MODEL="${POLISH_MODEL:-claude-haiku-4-5}"
API_KEY="${POLISH_API_KEY:-${ANTHROPIC_API_KEY:-}}"

if [[ -z "$API_KEY" ]]; then
  echo "FAIL: POLISH_API_KEY / ANTHROPIC_API_KEY is not set" >&2
  exit 1
fi

req() {
  local system_prompt="$1" user_text="$2"
  curl -sS --max-time 15 "${BASE_URL}/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg m "$MODEL" --arg s "$system_prompt" --arg u "$user_text" \
      '{model:$m, max_tokens:300, messages:[{role:"system",content:$s},{role:"user",content:$u}]}')" \
  | jq -er '.choices[0].message.content'
}

echo "== EN polish =="
req "$(cat config/handy/prompt-en-polish.txt)" \
    "um so i want add the new feature for login, you know, make it work good"

echo "== ZH-TW =="
req "$(cat config/handy/prompt-zh-tw.txt)" \
    "嗯就是说我想要在登录页面加一个新功能然后让它跑起来"

echo "PASS: endpoint, model, and both prompts respond"
