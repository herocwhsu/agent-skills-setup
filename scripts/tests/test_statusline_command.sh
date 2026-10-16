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
plain() { perl -pe 's/\e\[[0-9;]*m//g'; }
vis_len() { plain | perl -CS -0777 -ne 'print length'; }

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
out=$(plain < "$tmp_out")
elapsed=$(cat "$tmp_time")
rm -f "$tmp_out" "$tmp_time"
if perl -e "exit !($elapsed < 1.5)"; then
  ok "returns without waiting for EOF (${elapsed}s)"
else
  bad "returns without waiting for EOF" "took ${elapsed}s"
fi
[[ "$out" == *"work"* && "$out" == *"1% 1k/200k"* ]] \
  && ok "renders cwd and ctx with stdin open" \
  || bad "renders cwd and ctx with stdin open" "$out"

# stdin closed after the payload, like Claude Code
out=$(printf '%s' "$PAYLOAD" | COLUMNS=120 bash "$SCRIPT" | plain)
[[ "$out" == *"work"* && "$out" == *"1% 1k/200k"* ]] \
  && ok "renders cwd and ctx with stdin closed" \
  || bad "renders cwd and ctx with stdin closed" "$out"

# a brace inside a JSON string must not end the read early
out=$( { printf '%s' '{"cwd":"/tmp/a}b","context_window":{"total_input_tokens":1000,"context_window_size":200000}}'; sleep 3; } \
  | COLUMNS=120 bash "$SCRIPT" | plain )
[[ "$out" == *"a}b"* && "$out" == *"1% 1k/200k"* ]] \
  && ok "brace inside a string does not truncate the payload" \
  || bad "brace inside a string does not truncate the payload" "$out"

# terminal_width in payload overrides COLUMNS and sets right padding properly
PAYLOAD_WIDE='{"cwd":"/tmp/work","context_window":{"total_input_tokens":1000,"context_window_size":200000},"terminal_width":200}'
out=$(printf '%s' "$PAYLOAD_WIDE" | COLUMNS=80 bash "$SCRIPT")
visible_len=$(printf '%s' "$out" | vis_len)
[[ "$visible_len" -ge 199 && "$visible_len" -le 200 ]] \
  && ok "payload terminal_width overrides COLUMNS (${visible_len} cols)" \
  || bad "payload terminal_width overrides COLUMNS" "got ${visible_len} cols"

# AGY payload: one adaptive line, fields dropped by priority to fit terminal_width
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO_CWD="$TMP/agent-skills-setup"
mkdir -p "$REPO_CWD"
git -C "$REPO_CWD" init -q
git -C "$REPO_CWD" symbolic-ref HEAD refs/heads/feat-x

agy_payload() {
  jq -nc --arg cwd "$1" --argjson w "$2" '{
    cwd: $cwd, terminal_width: $w,
    model: {display_name: "Gemini 3.8 Flash (High)", effort: "high"},
    context_window: {total_input_tokens: 70000, total_output_tokens: 500,
      context_window_size: 1048576, used_percentage: 7, current_usage: null},
    quota: {"3p-5h": {remaining_fraction: 1}, "gemini-5h": {remaining_fraction: 0.8229455},
      "gemini-weekly": {remaining_fraction: 0.89}}}'
}

raw=$(agy_payload "$REPO_CWD" 160 | bash "$SCRIPT")
out=$(printf '%s' "$raw" | plain)
[[ "$raw" != *$'\n'* ]] && ok "prints a single line" || bad "prints a single line" "newline in output"
for want in "[Gemini 3.8 Flash (High)]" "agent-skills-setup" "git:(feat-x)" "7% 70k/1.0M" "5h 82%"; do
  [[ "$out" == *"$want"* ]] && ok "160 cols shows: $want" || bad "160 cols shows: $want" "$out"
done

for w in 80 60 40; do
  out=$(agy_payload "$REPO_CWD" "$w" | bash "$SCRIPT")
  len=$(printf '%s' "$out" | vis_len)
  [[ "$len" -le "$w" ]] && ok "fits $w cols (${len})" || bad "fits $w cols" "got ${len} cols"
  [[ "$(printf '%s' "$out" | plain)" == *"7%"* ]] && ok "$w cols keeps context percent" || bad "$w cols keeps context percent" "$(printf '%s' "$out" | plain)"
done

out=$(agy_payload "$REPO_CWD" 80 | bash "$SCRIPT" | plain)
[[ "$out" == *"5h 82%"* && "$out" == *"70k/1.0M"* ]] \
  && ok "80 cols keeps quota and tokens" || bad "80 cols keeps quota and tokens" "$out"
out=$(agy_payload "$REPO_CWD" 60 | bash "$SCRIPT" | plain)
[[ "$out" != *"git:("* && "$out" == *"agent-skills-setup"* && "$out" == *"70k/1.0M"* ]] \
  && ok "60 cols drops branch before cwd and tokens" || bad "60 cols drops branch before cwd and tokens" "$out"

# fresh session: zero tokens so far must still show context and quota
FRESH='{"cwd":"/tmp/a","model":{"display_name":"G"},"context_window":{"total_input_tokens":0,"context_window_size":1000000,"used_percentage":0,"current_usage":null},"quota":{"gemini-5h":{"remaining_fraction":0.5}},"terminal_width":80}'
out=$(printf '%s' "$FRESH" | bash "$SCRIPT" | plain)
[[ "$out" == *"0% 0/1.0M"* && "$out" == *"5h 50%"* ]] \
  && ok "zero-token fresh session shows context and quota" \
  || bad "zero-token fresh session shows context and quota" "$out"

# wide characters take two cells: the line must still fit
WIDE='{"cwd":"/tmp/專案目錄測試","model":{"display_name":"模型"},"context_window":{"total_input_tokens":5000,"context_window_size":10000,"used_percentage":50},"terminal_width":30}'
cells=$(printf '%s' "$WIDE" | bash "$SCRIPT" | plain | perl -CS -MEncode -ne 'my $n=0; for (split //) { $n += (/[\x{1100}-\x{115F}\x{2E80}-\x{A4CF}\x{AC00}-\x{D7A3}\x{F900}-\x{FAFF}\x{FE30}-\x{FE6F}\x{FF00}-\x{FF60}]/) ? 2 : 1 } print $n')
[[ "$cells" -le 30 ]] && ok "CJK cwd fits 30 cols (${cells} cells)" || bad "CJK cwd fits 30 cols" "${cells} cells"

# trailing slash and root cwd still name a directory
out=$(printf '%s' '{"cwd":"/tmp/proj/","terminal_width":80}' | bash "$SCRIPT" | plain)
[[ "$out" == *"proj"* ]] && ok "trailing-slash cwd shows its directory" || bad "trailing-slash cwd shows its directory" "[$out]"
out=$(printf '%s' '{"cwd":"/","terminal_width":80}' | bash "$SCRIPT" | plain)
[[ "$out" == *"/"* ]] && ok "root cwd shows /" || bad "root cwd shows /" "[$out]"

# output tokens: shown when above 0, dropped before the token detail when narrow
out=$(agy_payload "$REPO_CWD" 160 | bash "$SCRIPT" | plain)
[[ "$out" == *"out 500"* ]] && ok "160 cols shows output tokens" || bad "160 cols shows output tokens" "$out"
out=$(agy_payload "$REPO_CWD" 60 | bash "$SCRIPT" | plain)
[[ "$out" != *"out "* && "$out" == *"70k/1.0M"* ]] \
  && ok "60 cols drops output tokens before the token detail" || bad "60 cols drops output tokens before the token detail" "$out"
out=$(printf '%s' "$FRESH" | bash "$SCRIPT" | plain)
[[ "$out" != *"out "* ]] && ok "zero output tokens are not shown" || bad "zero output tokens are not shown" "$out"

# a count that rounds up to a million reads 1.0M, not 1000k
NEAR='{"cwd":"/tmp/a","context_window":{"total_input_tokens":999600,"total_output_tokens":999500,"context_window_size":1048576,"used_percentage":95},"terminal_width":120}'
out=$(printf '%s' "$NEAR" | bash "$SCRIPT" | plain)
[[ "$out" != *"1000k"* && "$out" == *"1.0M/1.0M"* && "$out" == *"out 1.0M"* ]] \
  && ok "counts near a million read 1.0M" || bad "counts near a million read 1.0M" "$out"

# the 5h limit shown follows the model's family, not the lowest of all buckets
quota_payload() {
  jq -nc --arg m "$1" --argjson q "$2" '{cwd:"/tmp/a", terminal_width:160, model:{display_name:$m},
    context_window:{total_input_tokens:1000, context_window_size:200000, used_percentage:1}, quota:$q}'
}
Q_BOTH='{"gemini-5h":{"remaining_fraction":0.59},"3p-5h":{"remaining_fraction":0},"gemini-weekly":{"remaining_fraction":0.88}}'
Q_3P_HIGH='{"gemini-5h":{"remaining_fraction":0.1},"3p-5h":{"remaining_fraction":0.8}}'
out=$(quota_payload "Gemini 4 Argon (Medium)" "$Q_BOTH" | bash "$SCRIPT" | plain)
[[ "$out" == *"5h 59%"* ]] && ok "a Gemini model shows gemini-5h, not the lower 3p-5h" || bad "a Gemini model shows gemini-5h, not the lower 3p-5h" "$out"
out=$(quota_payload "Claude Opus 5" "$Q_3P_HIGH" | bash "$SCRIPT" | plain)
[[ "$out" == *"5h 80%"* ]] && ok "a Claude model shows 3p-5h, not the lower gemini-5h" || bad "a Claude model shows 3p-5h, not the lower gemini-5h" "$out"
out=$(quota_payload "GPT-6" "$Q_3P_HIGH" | bash "$SCRIPT" | plain)
[[ "$out" == *"5h 80%"* ]] && ok "a GPT model shows 3p-5h" || bad "a GPT model shows 3p-5h" "$out"
out=$(quota_payload "Mystery Model" "$Q_3P_HIGH" | bash "$SCRIPT" | plain)
[[ "$out" == *"5h 10%"* ]] && ok "an unknown model name shows the lowest 5h bucket" || bad "an unknown model name shows the lowest 5h bucket" "$out"
out=$(quota_payload "Gemini 4 Argon (Medium)" '{"3p-5h":{"remaining_fraction":0.3}}' | bash "$SCRIPT" | plain)
[[ "$out" == *"5h 30%"* ]] && ok "a missing family bucket falls back to the lowest" || bad "a missing family bucket falls back to the lowest" "$out"
out=$(quota_payload "" "$Q_BOTH" | bash "$SCRIPT" | plain)
[[ "$out" == *"5h 0%"* ]] && ok "an empty model name falls back to the lowest" || bad "an empty model name falls back to the lowest" "$out"
out=$(quota_payload "Gemini 4 Argon (Medium)" '{"gemini-5h":"x","3p-5h":null}' | bash "$SCRIPT" | plain)
[[ "$out" == *"1% 1k/200k"* && "$out" != *"5h "* ]] && ok "a malformed quota does not blank the line" || bad "a malformed quota does not blank the line" "$out"

# out-of-range fractions are ignored, so the valid fallback bucket still shows
out=$(quota_payload "Gemini 4 Argon (Medium)" '{"gemini-5h":{"remaining_fraction":-0.5}}' | bash "$SCRIPT" | plain)
[[ "$out" == *"1% 1k/200k"* && "$out" != *"5h "* ]] && ok "a negative remaining_fraction shows no quota" || bad "a negative remaining_fraction shows no quota" "$out"
out=$(quota_payload "Gemini 4 Argon (Medium)" '{"gemini-5h":{"remaining_fraction":1.5},"3p-5h":{"remaining_fraction":0.4}}' | bash "$SCRIPT" | plain)
[[ "$out" == *"5h 40%"* ]] && ok "an over-range own bucket falls back to the valid lowest one" || bad "an over-range own bucket falls back to the valid lowest one" "$out"
out=$(quota_payload "Gemini 4 Argon (Medium)" '{"gemini-5h":{"remaining_fraction":1e999}}' | bash "$SCRIPT" | plain)
[[ "$out" != *"e+"* && "$out" != *"5h "* ]] && ok "an infinite remaining_fraction shows no quota" || bad "an infinite remaining_fraction shows no quota" "$out"

# a model that is not an object must not blank the whole line
out=$(printf '%s' '{"cwd":"/tmp/a","terminal_width":160,"model":"Gemini","context_window":{"total_input_tokens":1000,"context_window_size":200000,"used_percentage":1}}' | bash "$SCRIPT" | plain)
[[ "$out" == *"1% 1k/200k"* ]] && ok "a string model does not blank the line" || bad "a string model does not blank the line" "[$out]"

# install_statusline, each case in its own HOME so real ~/.gemini and ~/.claude
# are never touched.
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
[[ "$(jq '.statusLine | has("stack_with_default")' "$h/.gemini/antigravity-cli/settings.json")" == "false" \
   && "$(jq 'has("stack_with_default")' "$h/.gemini/antigravity-cli/settings.json")" == "false" ]] \
  && ok "gemini fresh install writes no stack_with_default anywhere (absent is off)" \
  || bad "gemini fresh install writes no stack_with_default anywhere (absent is off)" "$(cat "$h/.gemini/antigravity-cli/settings.json")"

# an old install left stack_with_default true at the top level, where AGY ignores it
h="$TMP/legacy"; d="$h/.gemini/antigravity-cli"; mkdir -p "$d"
printf '{"statusLine":{"type":"command","command":"bash %s","enabled":true},"stack_with_default":true,"model":"m"}\n' \
  "$d/statusline-command.sh" > "$d/settings.json"
( HOME="$h"; export HOME
  source "$REPO_DIR/scripts/_lib.sh"
  install_statusline gemini "$REPO_DIR" >/dev/null )
[[ "$(jq '.statusLine | has("stack_with_default")' "$d/settings.json")" == "false" \
   && "$(jq 'has("stack_with_default")' "$d/settings.json")" == "false" \
   && "$(jq -r '.model' "$d/settings.json")" == "m" ]] \
  && ok "an old top-level stack_with_default true is removed" \
  || bad "an old top-level stack_with_default true is removed" "$(cat "$d/settings.json")"

# a nested true left by hand would draw AGY's own line above ours: our statusLine owns the row, so it goes
h="$TMP/nested-true"; d="$h/.gemini/antigravity-cli"; mkdir -p "$d"
printf '{"statusLine":{"type":"command","command":"bash %s","enabled":true,"stack_with_default":true},"model":"m"}\n' \
  "$d/statusline-command.sh" > "$d/settings.json"
( HOME="$h"; export HOME
  source "$REPO_DIR/scripts/_lib.sh"
  install_statusline gemini "$REPO_DIR" >/dev/null )
[[ "$(jq '.statusLine | has("stack_with_default")' "$d/settings.json")" == "false" \
   && "$(jq -r '.model' "$d/settings.json")" == "m" ]] \
  && ok "a nested stack_with_default true is removed on refresh" \
  || bad "a nested stack_with_default true is removed on refresh" "$(cat "$d/settings.json")"

# no jq: the python fallback writes the same shape
h="$TMP/nojq"; d="$h/.gemini/antigravity-cli"; mkdir -p "$d" "$TMP/nojq-bin"
REAL_PY=$(python3 -c 'import sys; print(sys.executable)')
for t in bash cp chmod mkdir dirname grep cat; do p=$(command -v "$t") && ln -sf "$p" "$TMP/nojq-bin/$t"; done
ln -sf "$REAL_PY" "$TMP/nojq-bin/python3"
printf '{"colorScheme":"dark","stack_with_default":true}\n' > "$d/settings.json"
( HOME="$h"; export HOME; PATH="$TMP/nojq-bin"
  source "$REPO_DIR/scripts/_lib.sh"
  install_statusline gemini "$REPO_DIR" >/dev/null 2>&1 )
[[ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("stack_with_default" in d["statusLine"], "stack_with_default" in d, d["colorScheme"])' "$d/settings.json")" == "False False dark" ]] \
  && ok "python fallback writes no stack_with_default and removes the top-level one" \
  || bad "python fallback writes no stack_with_default and removes the top-level one" "$(cat "$d/settings.json")"

# a foreign AGY statusLine is left alone, including by setup-host.sh
h="$TMP/foreign-agy"; d="$h/.gemini/antigravity-cli"; mkdir -p "$d"
printf '{"statusLine":{"type":"command","command":"node custom.js"},"theme":"dark"}\n' > "$d/settings.json"
before=$(cat "$d/settings.json")
( HOME="$h"; export HOME
  source "$REPO_DIR/scripts/_lib.sh"
  install_statusline gemini "$REPO_DIR" >/dev/null )
[[ "$(cat "$d/settings.json")" == "$before" ]] \
  && ok "install_statusline leaves a foreign AGY statusLine untouched" \
  || bad "install_statusline leaves a foreign AGY statusLine untouched" "$(cat "$d/settings.json")"
# setup-host.sh runs interactively and also touches tmux/MCP: give it a throwaway HOME,
# a PATH with only agy and the basics, and closed stdin so no prompt can wait.
sh_bin="$TMP/sethost-bin"; mkdir -p "$sh_bin"
for t in bash jq cp chmod mkdir dirname basename grep sed cat ls sort tail head tr mv rm date uname env awk; do
  tp=$(command -v "$t") && ln -sf "$tp" "$sh_bin/$t"
done
ln -sf "$REAL_PY" "$sh_bin/python3"
printf '#!/bin/sh\nexit 0\n' > "$sh_bin/agy"; chmod +x "$sh_bin/agy"
sh_out=$( HOME="$h" PATH="$sh_bin" NTFY_URL="https://ntfy.invalid/t" NTFY_TOKEN="x" \
  bash "$REPO_DIR/scripts/setup-host.sh" </dev/null 2>&1 ) || true
[[ "$sh_out" == *"Patching ~/.gemini/antigravity-cli/settings.json"* ]] \
  && ok "setup-host.sh reached the AGY settings step in the test" \
  || bad "setup-host.sh reached the AGY settings step in the test" "$(printf '%s' "$sh_out" | tail -4)"
[[ "$(cat "$d/settings.json")" == "$before" ]] \
  && ok "setup-host.sh leaves a foreign AGY statusLine untouched" \
  || bad "setup-host.sh leaves a foreign AGY statusLine untouched" "$(cat "$d/settings.json")"

# settings already point at our script: the stale copy gets refreshed and stack_with_default removed
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
[[ "$(jq '.statusLine | has("stack_with_default")' "$d/settings.json")" == "false" \
   && "$(jq 'has("stack_with_default")' "$d/settings.json")" == "false" \
   && "$(jq -r '.colorScheme' "$d/settings.json")" == "dark" ]] \
  && ok "refresh removes stack_with_default and keeps other keys" \
  || bad "refresh removes stack_with_default and keeps other keys" "$(cat "$d/settings.json")"

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
