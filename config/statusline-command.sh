#!/usr/bin/env bash
# Claude Code / AGY statusLine — one line: [model] cwd git:(branch)   context | 5h quota
# Fields are dropped by priority until the line fits the terminal width.
# The 5h limit is the model family's own bucket (gemini-5h, or 3p-5h for Claude/GPT), else the lowest.

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

# One jq pass; unit separator keeps empty fields from collapsing in `read`.
IFS=$'\x1f' read -r cwd model pct used total quota out_tok term_width < <(
  printf '%s' "$input" | jq -r '
    def frac: if type == "object" then .remaining_fraction else null end | select(type == "number" and . >= 0 and . <= 1);
    [
      (.cwd // ""),
      ((.model | if type == "object" then .display_name else null end) // "" | tostring),
      (.context_window.used_percentage | if . == null then "" else round end),
      (
        if ((.context_window.total_input_tokens // 0) > 0) then
          .context_window.total_input_tokens
        elif (.context_window.current_usage != null) then
          ((.context_window.current_usage.input_tokens // 0) +
           (.context_window.current_usage.cache_creation_input_tokens // 0) +
           (.context_window.current_usage.cache_read_input_tokens // 0))
        elif (.context_window.context_window_size // 0) > 0 then
          0
        else
          ""
        end
      ),
      (.context_window.context_window_size // ""),
      (
        ((.model | if type == "object" then .display_name else null end) // "" | tostring) as $m
        | ((.quota | if type == "object" then . else {} end)) as $q
        | (if ($m | startswith("Gemini")) then "gemini-5h"
           elif ($m | test("^(Claude|GPT)")) then "3p-5h"
           else "" end) as $key
        | ([$q[$key] | frac] | .[0]) as $own
        | ([$q | to_entries[] | select(.key | endswith("-5h")) | .value | frac]
           | if length == 0 then null else min end) as $low
        | ($own // $low)
        | if . == null then "" else ((. * 100) | round) end
      ),
      (.context_window.total_output_tokens // ""),
      (.terminal_width // "")
    ] | map(tostring) | join("\u001f")
  ' 2>/dev/null || true
)

cols="${term_width:-${COLUMNS:-}}"
if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]]; then
  cols=$(tmux display-message -p '#{pane_width}' 2>/dev/null || tput cols 2>/dev/null || echo 80)
fi

fmt_tokens() {
  local n=$1 t
  if [ "$n" -ge 999500 ]; then
    t=$(( (n * 10 + 500000) / 1000000 ))
    printf '%d.%dM' $((t / 10)) $((t % 10))
  elif [ "$n" -ge 1000 ]; then
    printf '%dk' $(( (n + 500) / 1000 ))
  else
    printf '%d' "$n"
  fi
}

cells() {
  if command -v perl &>/dev/null; then
    printf '%s' "$1" | perl -CS -ne '$n = 0; for (split //) { $n += (/[\x{1100}-\x{115F}\x{2E80}-\x{A4CF}\x{AC00}-\x{D7A3}\x{F900}-\x{FAFF}\x{FE30}-\x{FE6F}\x{FF00}-\x{FF60}\x{1F300}-\x{1FAFF}]/) ? 2 : 1 } print $n'
  else
    printf '%s' "${#1}"
  fi
}

branch=""
[ -n "$cwd" ] && branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null)
dir="${cwd%/}"; dir="${dir##*/}"
[ -z "$dir" ] && [ -n "$cwd" ] && dir="/"

have_ctx=0
if [ -n "$used" ] && [ -n "$total" ] && [ "$total" -gt 0 ] 2>/dev/null; then
  have_ctx=1
  [ -z "$pct" ] && pct=$(( (used * 100 + total / 2) / total ))
  ctx_detail="${pct}% $(fmt_tokens "$used")/$(fmt_tokens "$total")"
  ctx_full="$ctx_detail"
  if [ -n "$out_tok" ] && [ "$out_tok" -gt 0 ] 2>/dev/null; then
    ctx_full="$ctx_detail out $(fmt_tokens "$out_tok")"
  fi
  if [ "$pct" -ge 85 ]; then ctx_color=31; elif [ "$pct" -ge 70 ]; then ctx_color=33; else ctx_color=32; fi
  filled=$(( (pct + 5) / 10 )); [ "$filled" -gt 10 ] && filled=10
  bar=""; i=0
  while [ "$i" -lt 10 ]; do
    if [ "$i" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
    i=$((i + 1))
  done
fi

model_w=0; dir_w=0; branch_w=0
[ -n "$model" ] && model_w=$(cells "$model")
[ -n "$dir" ] && dir_w=$(cells "$dir")
[ -n "$branch" ] && branch_w=$(cells "$branch")

# Drop order, first to last: bar and output tokens, branch, quota, model, cwd, token detail.
for lvl in 0 1 2 3 4 5 6; do
  left=""; left_len=0; right=""; right_len=0

  if [ "$lvl" -le 3 ] && [ -n "$model" ]; then
    left="$(printf '\033[36m[%s]\033[00m' "$model")"; left_len=$(( $model_w + 2 ))
  fi
  if [ "$lvl" -le 4 ] && [ -n "$dir" ]; then
    [ -n "$left" ] && { left="$left "; left_len=$((left_len + 1)); }
    left="$left$(printf '\033[01;34m%s\033[00m' "$dir")"; left_len=$(( left_len + dir_w ))
  fi
  if [ "$lvl" -le 1 ] && [ -n "$branch" ]; then
    [ -n "$left" ] && { left="$left "; left_len=$((left_len + 1)); }
    left="$left$(printf '\033[35mgit:(\033[33m%s\033[35m)\033[00m' "$branch")"; left_len=$(( left_len + branch_w + 6 ))
  fi

  if [ "$have_ctx" -eq 1 ]; then
    ctx_text="${pct}%"; [ "$lvl" -le 5 ] && ctx_text="$ctx_detail"; [ "$lvl" -le 1 ] && ctx_text="$ctx_full"
    if [ "$lvl" -eq 0 ]; then
      right="$(printf '\033[%sm%s\033[00m ' "$ctx_color" "$bar")"; right_len=11
    fi
    right="$right$(printf '\033[%sm%s\033[00m' "$ctx_color" "$ctx_text")"; right_len=$(( right_len + ${#ctx_text} ))
  fi
  if [ "$lvl" -le 2 ] && [ -n "$quota" ]; then
    q="5h ${quota}%"
    if [ -n "$right" ]; then
      right="$right$(printf ' \033[02;37m│ %s\033[00m' "$q")"; right_len=$(( right_len + 3 + ${#q} ))
    else
      right="$(printf '\033[02;37m%s\033[00m' "$q")"; right_len=${#q}
    fi
  fi

  need=$(( left_len + right_len )); [ "$left_len" -gt 0 ] && [ "$right_len" -gt 0 ] && need=$(( need + 2 ))
  [ "$need" -le $(( cols - 1 )) ] && break
done

if [ -n "$right" ]; then
  pad=$(( cols - 1 - left_len - right_len ))
  if [ "$left_len" -gt 0 ] && [ "$pad" -lt 1 ]; then pad=1; fi
  [ "$pad" -lt 0 ] && pad=0
  printf '%s%*s%s' "$left" "$pad" "" "$right"
else
  printf '%s' "$left"
fi
