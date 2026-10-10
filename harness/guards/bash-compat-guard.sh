#!/usr/bin/env bash
# bash-compat-guard.sh — Stop/SubagentStop hook: block completion if any *.sh
# file uses a Bash 4+ construct that aborts under macOS /bin/bash 3.2:
# mapfile/readarray, associative arrays (declare/local/typeset -A), or ;& / ;;&
# case fallthrough. Exit 2 blocks; exit 0 allows.
#
# Exists because nothing else catches these: `bash -n` and shellcheck both
# accept them when the parsing bash is 5.x, which is what CI and Homebrew
# provide. init-repo.sh shipped `;&` for months and aborted on every macOS run
# while CI stayed green.
#
# Matches only in command position (line start, or after ; & | ( {), so
# comments and quoted strings that merely name a construct do not block.
set -euo pipefail

# Overridable so a test can point at a throwaway tree.
REPO_DIR="${BASH_COMPAT_GUARD_REPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

START='(^|[;&|({])[[:space:]]*'
PATTERN="${START}(mapfile|readarray)([[:space:]]|\$)"
PATTERN="$PATTERN|${START}(declare|local|typeset)[[:space:]]+(-[[:alpha:]]*[[:space:]]+)*-[[:alpha:]]*A"
PATTERN="$PATTERN|;;?&[[:space:]]*(#.*)?\$"

hits=""
while IFS= read -r f; do
  if h=$(grep -nE "$PATTERN" "$f" | grep -vE '^[0-9]+:[[:space:]]*#'); then
    hits="$hits$(printf '%s\n' "$h" | sed "s|^|  ${f#"$REPO_DIR"/}:|")"$'\n'
  fi
done < <(find "$REPO_DIR" \( -name .git -o -name .venv -o -name node_modules \) -prune \
           -o -type f -name '*.sh' -print | sort)

# A multi-line `python3 -c "` body must start at column 0: Python 3.14 dedents
# -c code, but 3.13 and older raise IndentationError. py-check.sh shipped an
# indented body that passed on this host's 3.14 and failed on CI's python3.
pyhits=""
while IFS= read -r f; do
  if h=$(awk '/python3?[[:space:]]+-c[[:space:]]+"$/ { open = NR; next }
              open && NR == open + 1 && /^[[:space:]]+[^[:space:]]/ { print NR ": " $0 }
              { open = 0 }' "$f"); [[ -n "$h" ]]; then
    pyhits="$pyhits$(printf '%s\n' "$h" | sed "s|^|  ${f#"$REPO_DIR"/}:|")"$'\n'
  fi
done < <(find "$REPO_DIR" \( -name .git -o -name .venv -o -name node_modules \) -prune \
           -o -type f -name '*.sh' -print | sort)

if [[ -n "$hits" || -n "$pyhits" ]]; then
  {
    if [[ -n "$hits" ]]; then
      echo "Blocked: Bash 4+ constructs abort under macOS /bin/bash 3.2 (see AGENTS.md Shell Portability):"
      printf '%s' "$hits"
    fi
    if [[ -n "$pyhits" ]]; then
      echo "Blocked: indented python -c body (IndentationError on Python <= 3.13; start it at column 0):"
      printf '%s' "$pyhits"
    fi
  } >&2
  exit 2
fi

exit 0
