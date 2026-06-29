#!/usr/bin/env bash
# Claude Code statusLine — mirrors bash PS1 (green user@host, blue cwd)
# Context usage right-aligned: [ctx: Xk/Yk]

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')
used=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
total=$(echo "$input" | jq -r '.context_window.context_window_size // empty')

user_host="$(whoami)@$(hostname -s)"
left_visible="${user_host}:${cwd}"

if [ -n "$used" ] && [ -n "$total" ]; then
  used_k=$(( (used + 500) / 1000 ))
  total_k=$(( (total + 500) / 1000 ))
  ctx_block="[ctx: ${used_k}k/${total_k}k]"

  cols="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
  left_len=${#left_visible}
  ctx_len=${#ctx_block}
  pad=$(( cols - left_len - 1 - ctx_len ))
  [ "$pad" -lt 1 ] && pad=1

  printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m%*s\033[02;37m%s\033[00m' \
    "$(whoami)" "$(hostname -s)" "$cwd" "$pad" "" "$ctx_block"
else
  printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m' \
    "$(whoami)" "$(hostname -s)" "$cwd"
fi
