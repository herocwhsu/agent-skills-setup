#!/usr/bin/env bash
# precommit-sh-check.sh — PreToolUse(Bash): block `git commit` when a staged
# *.sh file fails bash -n or shellcheck --severity=error. Checks the STAGED
# blob (git show :FILE), not the working tree. Exit 2 blocks; exit 0 allows.
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print(''); sys.exit(0)
print(d.get('tool_input',{}).get('command',''))
" 2>/dev/null)

# Only gate real `git commit`. Skip dry-run/help and non-commit commands.
case "$cmd" in
  *"git commit"*) : ;;
  *) exit 0 ;;
esac
case "$cmd" in
  *"--dry-run"*|*"--help"*) exit 0 ;;
esac
# Guard against 'commit' only inside a message: require the token 'commit'
# to follow 'git' as a subcommand.
echo "$cmd" | grep -Eq '(^|[[:space:]])git[[:space:]]+([^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)' || exit 0

# Must be in a git repo.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Portable (bash 3.2 / macOS /bin/bash has no `mapfile`).
staged=()
while IFS= read -r f; do
  [[ -n "$f" ]] && staged+=("$f")
done < <(git diff --cached --name-only --diff-filter=ACM | grep -E '\.sh$' || true)
[[ ${#staged[@]} -eq 0 ]] && exit 0

have_shellcheck=0
command -v shellcheck >/dev/null 2>&1 && have_shellcheck=1

fail=0
msgs=""
for f in "${staged[@]}"; do
  blob=$(git show ":$f" 2>/dev/null) || continue
  if ! printf '%s' "$blob" | bash -n - 2>/tmp/.sc.$$; then
    fail=1; msgs+="  $f: bash syntax error"$'\n'
  elif [[ "$have_shellcheck" -eq 1 ]]; then
    if ! printf '%s' "$blob" | shellcheck --severity=error - >/tmp/.sc.$$ 2>&1; then
      fail=1; msgs+="  $f: shellcheck error"$'\n'
    fi
  fi
done
rm -f /tmp/.sc.$$

if [[ "$fail" -eq 1 ]]; then
  {
    echo "Blocked: staged shell scripts have errors (fix before committing):"
    printf '%s' "$msgs"
    [[ "$have_shellcheck" -eq 0 ]] && echo "  (shellcheck not installed — only syntax checked)"
  } >&2
  exit 2
fi
exit 0
