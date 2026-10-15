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
[[ "$(jq -r '.stack_with_default' "$h/.gemini/antigravity-cli/settings.json")" == "false" ]] \
  && ok "gemini fresh install turns stack_with_default off" \
  || bad "gemini fresh install turns stack_with_default off" "not false"

# settings already point at our script: the stale copy gets refreshed and stack_with_default turned off
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
[[ "$(jq -r '.stack_with_default' "$d/settings.json")" == "false" ]] \
  && ok "refresh sets stack_with_default to false" \
  || bad "refresh sets stack_with_default to false" "not false"

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
