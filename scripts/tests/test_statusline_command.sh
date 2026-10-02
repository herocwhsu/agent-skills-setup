#!/usr/bin/env bash
# Tests config/statusline-command.sh against how each host feeds stdin.
#
# Antigravity CLI writes the JSON payload but never closes stdin, then kills the
# command on timeout ("signal: killed"), so the status line renders empty. The
# script must return as soon as the JSON object is complete, not wait for EOF.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_DIR/config/statusline-command.sh"

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

PAYLOAD='{"cwd":"/tmp/work","context_window":{"total_input_tokens":1000,"context_window_size":200000}}'

# stdin held open for 3s after the payload, like AGY. Time the reader side only:
# $(...) around the whole pipeline would also wait out the writer's sleep.
tmp_out=$(mktemp)
tmp_time=$(mktemp)
{ printf '%s' "$PAYLOAD"; sleep 3; } | {
  start=$(now)
  COLUMNS=120 bash "$SCRIPT" > "$tmp_out"
  perl -e "printf '%.2f', $(now) - $start" > "$tmp_time"
}
out=$(cat "$tmp_out")
elapsed=$(cat "$tmp_time")
rm -f "$tmp_out" "$tmp_time"
if perl -e "exit !($elapsed < 1.5)"; then
  ok "returns without waiting for EOF (${elapsed}s)"
else
  bad "returns without waiting for EOF" "took ${elapsed}s"
fi
[[ "$out" == *"/tmp/work"* && "$out" == *"[ctx: 1k/200k]"* ]] \
  && ok "renders cwd and ctx with stdin open" \
  || bad "renders cwd and ctx with stdin open" "$out"

# stdin closed after the payload, like Claude Code
out=$(printf '%s' "$PAYLOAD" | COLUMNS=120 bash "$SCRIPT")
[[ "$out" == *"/tmp/work"* && "$out" == *"[ctx: 1k/200k]"* ]] \
  && ok "renders cwd and ctx with stdin closed" \
  || bad "renders cwd and ctx with stdin closed" "$out"

# a brace inside a JSON string must not end the read early
out=$( { printf '%s' '{"cwd":"/tmp/a}b","context_window":{"total_input_tokens":1000,"context_window_size":200000}}'; sleep 3; } \
  | COLUMNS=120 bash "$SCRIPT" )
[[ "$out" == *"/tmp/a}b"* && "$out" == *"[ctx: 1k/200k]"* ]] \
  && ok "brace inside a string does not truncate the payload" \
  || bad "brace inside a string does not truncate the payload" "$out"

# terminal_width in payload overrides COLUMNS and sets right padding properly
PAYLOAD_WIDE='{"cwd":"/tmp/work","context_window":{"total_input_tokens":1000,"context_window_size":200000},"terminal_width":200}'
out=$(printf '%s' "$PAYLOAD_WIDE" | COLUMNS=80 bash "$SCRIPT")
visible_len=$(printf '%s' "$out" | perl -pe 's/\e\[[0-9;]*m//g' | wc -c | tr -d ' ')
[[ "$visible_len" -ge 199 && "$visible_len" -le 200 ]] \
  && ok "payload terminal_width overrides COLUMNS (${visible_len} cols)" \
  || bad "payload terminal_width overrides COLUMNS" "got ${visible_len} cols"

# install_statusline, each case in its own HOME so real ~/.gemini and ~/.claude
# are never touched.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# fresh AGY install writes the object form; AGY runs it (verified in a live session)
h="$TMP/fresh"; mkdir -p "$h"
res=$( HOME="$h"; export HOME
  # shellcheck source=scripts/_lib.sh
  source "$REPO_DIR/scripts/_lib.sh"
  install_statusline gemini "$REPO_DIR" >/dev/null
  jq -r '.statusLine | "\(.type) \(.command)"' "$h/.gemini/antigravity-cli/settings.json" )
[[ "$res" == "command bash $h/.gemini/antigravity-cli/statusline-command.sh" ]] \
  && ok "gemini fresh install writes command-object statusLine" \
  || bad "gemini fresh install writes command-object statusLine" "$res"
[[ "$(jq -r '.stack_with_default' "$h/.gemini/antigravity-cli/settings.json")" == "true" ]] \
  && ok "gemini fresh install enables stack_with_default" \
  || bad "gemini fresh install enables stack_with_default" "missing stack_with_default"

# settings already point at our script: the stale copy gets refreshed and stack_with_default ensured
h="$TMP/stale"; d="$h/.gemini/antigravity-cli"; mkdir -p "$d"
echo "stale" > "$d/statusline-command.sh"
printf '{"statusLine":{"type":"command","command":"bash %s","enabled":true},"colorScheme":"dark"}\n' \
  "$d/statusline-command.sh" > "$d/settings.json"
( HOME="$h"; export HOME
  source "$REPO_DIR/scripts/_lib.sh"
  install_statusline gemini "$REPO_DIR" >/dev/null )
cmp -s "$d/statusline-command.sh" "$REPO_DIR/config/statusline-command.sh" \
  && ok "stale installed script is refreshed" \
  || bad "stale installed script is refreshed" "copy differs from config/statusline-command.sh"
[[ "$(jq -r '.stack_with_default' "$d/settings.json")" == "true" ]] \
  && ok "refresh ensures stack_with_default is true" \
  || bad "refresh ensures stack_with_default is true" "missing stack_with_default"

# a foreign statusLine (e.g. claude-hud) is left alone and no script is copied
h="$TMP/foreign"; mkdir -p "$h/.claude"
echo '{"statusLine":{"type":"command","command":"node hud.js"}}' > "$h/.claude/settings.json"
before=$(cat "$h/.claude/settings.json")
( HOME="$h"; export HOME
  source "$REPO_DIR/scripts/_lib.sh"
  install_statusline claude "$REPO_DIR" >/dev/null )
[[ "$(cat "$h/.claude/settings.json")" == "$before" && ! -e "$h/.claude/statusline-command.sh" ]] \
  && ok "foreign statusLine is untouched" \
  || bad "foreign statusLine is untouched" "settings or script changed"

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
