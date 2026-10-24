#!/usr/bin/env bash
# handover-guard.sh — PostToolUse scripts/handover/*.sh: owner-run scripts follow
# the handover contract. `--all` checks every one, for the repo's init.sh.
#   log file   output goes to a log (tee or a redirect to a *log* path)
#   no secret  no typed password: -K, ansible -k/-J, --ask-*pass, *ASK_PASS=true, read -s
#   Rollback:  a header line naming the rollback, or "none" and why
#   Resume:    a header line, and a marker file the script tests and writes,
#              so a rerun picks up where it stopped
# Found 2026-10-23: hangar's finish script took four runs (mistyped -K, no log,
# no resume point). The checks are static; they show the parts exist, not that
# they work. Known misses: a read -s whose prompt holds ";" or "<" passes, and a
# trailing comment that names -K and holds a quote blocks.
set -euo pipefail

# A flag token: starts the word, or follows a quote, "(" or "=" (arrays, "-K").
pre='(^|[[:space:]"'"'"'(=])' post='([[:space:]"'"'"');|&]|$)'

check() { # <file> -> prints one line per broken rule
  local f="$1" code nosudo var
  # Drop comments; a "#" with a quote after it may sit inside a string, so it stays.
  code=$(grep -vE '^[[:space:]]*#' "$f" | sed "s/[[:space:]]#[^\"']*\$//" || true)
  # sudo -K drops cached credentials, curl -K names a config file and kill -KILL
  # is a signal; none of them asks.
  nosudo=$(sed -E -e 's/(sudo|curl([[:space:]]+[^[:space:];|&]+)*)[[:space:]]+-K([[:space:]]|$)/\1\3/g' \
                  -e 's/(kill|pkill|killall)[[:space:]]+-[A-Z]+/\1/g' <<< "$code")
  # Here-strings, not pipes: with pipefail an early grep -q exit fails the pipe.
  if grep -qE -- "${pre}-[A-Za-z]*K[A-Za-z]*${post}" <<< "$nosudo" ||
     grep -qE -- "ansible[^;|&]*${pre}-[A-Za-z]*[kJ][A-Za-z]*${post}" <<< "$code" ||
     grep -qE -- '--ask-[a-z-]*pass|ASK_[A-Z_]*PASS=["'"'"']?([Tt]rue|TRUE|1|[Yy]es)' <<< "$code" ||
     grep -qE '(^|[[:space:];|&(])read([[:space:]]+[^;|&<]*)?[[:space:]]+-[A-Za-z]*s[A-Za-z]*([[:space:]]|$)' <<< "$code"; then
    echo "typed secret: read the password from a 0600 file (e.g. --become-password-file), not -K, -k, -J, --ask-*pass, ASK_PASS=true or read -s"
  fi
  grep -qE '(tee([[:space:]]+-a)?|>)[[:space:]]*"?(\$\{?[A-Za-z0-9_]*[Ll][Oo][Gg]|[^[:space:]";|&]*\.log)' <<< "$code" ||
    echo "no log file: send the output to a log (tee -a \"\$log\"), so a failed run can be read afterwards"
  grep -qE '^[[:space:]]*#[[:space:]]*Rollback:[[:space:]]*[^[:space:]]' "$f" ||
    echo "no '# Rollback:' header line: name the rollback command, or 'none' and why"
  grep -qE '^[[:space:]]*#[[:space:]]*Resume:[[:space:]]*[^[:space:]]' "$f" ||
    echo "no '# Resume:' header line: say what a rerun after a failure does"
  # The log grows on every run, so it never marks a finished step.
  for var in $(printf '%s\n' "$code" | grep -oE -- '(\[\[?|test|&&|\|\||!|\(|-a|-o)[[:space:]]+-[fe][[:space:]]+"?\$\{?[A-Za-z_][A-Za-z0-9_]*' |
               sed -E 's/.*\$\{?//' | grep -viE 'log' | sort -u); do
    if grep -qE "(>|touch[[:space:]]+)[[:space:]]*\"?\\\$\{?$var([^A-Za-z0-9_]|\$)" <<< "$code"; then
      return 0
    fi
  done
  echo "no marker file: write a state file at each finished step and test it on rerun ([[ -f \"\$done_file\" ]])"
}

report() { # <file> -> 0 ok, 1 broken
  local problems
  problems=$(check "$1")
  [[ -z "$problems" ]] && return 0
  echo "handover contract broken in $1:" >&2
  printf '%s\n' "$problems" | sed 's/^/  /' >&2
  return 1
}

if [[ "${1:-}" == --all ]]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  rc=0
  [[ -d "$root/scripts/handover" ]] || exit 0
  while IFS= read -r f; do
    report "$f" || rc=2
  done < <(find "$root/scripts/handover" -type f -name '*.sh' | sort)
  exit "$rc"
fi

file=$(python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{}) or {}
print(i.get('path') or i.get('file_path') or '')
" 2>/dev/null) || file=""   # unparseable input fails open

case "$file" in
  scripts/handover/*.sh|*/scripts/handover/*.sh) ;;
  *) exit 0 ;;
esac
[[ -f "$file" ]] || exit 0
report "$file" || exit 2
