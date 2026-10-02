#!/usr/bin/env bash
# Claude Code / AGY statusLine — mirrors bash PS1 (green user@host, blue cwd)
# Context usage right-aligned: [ctx: Xk/Yk]

# Antigravity CLI never closes stdin, so `cat` (or jq) would block until the host
# kills the command. Stop reading once the top-level JSON object closes.
if command -v perl &>/dev/null; then
  input=$(perl -e '
    my $buf = "";
    $SIG{ALRM} = sub { print $buf; exit };
    alarm 1;
    my ($depth, $in_str, $esc, $started) = (0, 0, 0, 0);
    while (sysread(STDIN, my $c, 1)) {
      $buf .= $c;
      if ($in_str) {
        if ($esc) { $esc = 0 } elsif ($c eq "\\") { $esc = 1 } elsif ($c eq "\"") { $in_str = 0 }
        next;
      }
      if ($c eq "\"") { $in_str = 1 }
      elsif ($c eq "{") { $depth++; $started = 1 }
      elsif ($c eq "}") { $depth--; last if $started && $depth == 0 }
    }
    print $buf;
  ')
else
  input=$(cat)
fi

# Parse all fields in one single jq pass to ensure < 25ms execution time
IFS=$'\t' read -r cwd used total term_width < <(
  printf '%s' "$input" | jq -r '
    [
      (.cwd // ""),
      (
        if ((.context_window.total_input_tokens // 0) > 0) then
          .context_window.total_input_tokens
        elif (.context_window.current_usage != null) then
          ((.context_window.current_usage.input_tokens // 0) +
           (.context_window.current_usage.cache_creation_input_tokens // 0) +
           (.context_window.current_usage.cache_read_input_tokens // 0))
        else
          ""
        end
      ),
      (.context_window.context_window_size // ""),
      (.terminal_width // "")
    ] | @tsv
  ' 2>/dev/null || true
)

user_host="$(whoami)@$(hostname -s)"
left_visible="${user_host}:${cwd}"

if [ -n "$used" ] && [ -n "$total" ]; then
  used_k=$(( (used + 500) / 1000 ))
  total_k=$(( (total + 500) / 1000 ))
  ctx_block="[ctx: ${used_k}k/${total_k}k]"

  cols="${term_width:-${COLUMNS:-}}"
  if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]]; then
    cols=$(tmux display-message -p '#{pane_width}' 2>/dev/null || tput cols 2>/dev/null || echo 80)
  fi
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
