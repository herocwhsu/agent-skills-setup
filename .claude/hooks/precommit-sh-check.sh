#!/usr/bin/env bash
# precommit-sh-check.sh — PreToolUse(Bash): block `git commit` when a staged
# *.sh file fails bash -n or shellcheck --severity=error. Checks the STAGED
# blob (git show :FILE), not the working tree. Exit 2 blocks; exit 0 allows.
set -euo pipefail

input=$(cat)
# Classify the command with proper shell tokenization (shlex), NOT substring
# matching: decide whether it is a real `git commit` that should be gated.
# Prints GATE to gate, or nothing to skip. Token-level parsing means flag-like
# text inside the -m/-F message (e.g. `-m "fix --dry-run"`) stays one token and
# cannot be mistaken for a real --dry-run/--help flag, and `commit` inside a
# message cannot be mistaken for the subcommand. Fails open (skip) on any parse
# error, matching the rest of the hook's fail-open posture.
decision=$(printf '%s' "$input" | python3 -c "
import json, shlex, sys
try:
    d = json.load(sys.stdin)
    cmd = (
        d.get('tool_input', {}).get('command')
        or d.get('toolCall', {}).get('args', {}).get('CommandLine')
        or ''
    )
    toks = shlex.split(cmd)
except Exception:
    sys.exit(0)  # unparseable -> skip (fail open)

# Find a 'git' token, then its first non-option token = the subcommand.
# Consume git global options that take a value (-C <path>, -c <kv>).
i = 0
while i < len(toks):
    if toks[i] == 'git':
        j = i + 1
        while j < len(toks):
            t = toks[j]
            if t in ('-C', '-c'):
                j += 2; continue
            if t.startswith('-'):
                j += 1; continue
            break
        if j < len(toks) and toks[j] == 'commit':
            rest = toks[j+1:]
            if '--dry-run' in rest or '--help' in rest or '-h' in rest:
                sys.exit(0)  # not a real committing invocation -> skip
            print('GATE')
        sys.exit(0)
    i += 1
" 2>/dev/null)

is_agy=0
if printf '%s' "$input" | python3 -c "import json, sys; d=json.load(sys.stdin); sys.exit(0 if 'toolCall' in d or 'conversationId' in d else 1)" 2>/dev/null; then
  is_agy=1
fi

if [[ "$decision" != "GATE" ]]; then
  [[ "$is_agy" -eq 1 ]] && echo '{"decision": "allow"}'
  exit 0
fi

# Must be in a git repo.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  [[ "$is_agy" -eq 1 ]] && echo '{"decision": "allow"}'
  exit 0
fi

# Portable (bash 3.2 / macOS /bin/bash has no `mapfile`).
staged=()
while IFS= read -r f; do
  [[ -n "$f" ]] && staged+=("$f")
done < <(git diff --cached --name-only --diff-filter=ACM | grep -E '\.sh$' || true)
if [[ ${#staged[@]} -eq 0 ]]; then
  [[ "$is_agy" -eq 1 ]] && echo '{"decision": "allow"}'
  exit 0
fi

have_shellcheck=0
command -v shellcheck >/dev/null 2>&1 && have_shellcheck=1

scratch=$(mktemp)
trap 'rm -f "$scratch"' EXIT
fail=0
msgs=""
for f in "${staged[@]}"; do
  blob=$(git show ":$f" 2>/dev/null) || continue
  if ! printf '%s' "$blob" | bash -n - 2>"$scratch"; then
    fail=1; msgs+="  $f: bash syntax error"$'\n'
  elif [[ "$have_shellcheck" -eq 1 ]]; then
    if ! printf '%s' "$blob" | shellcheck --severity=error - >"$scratch" 2>&1; then
      fail=1; msgs+="  $f: shellcheck error"$'\n'
    fi
  fi
done

if [[ "$fail" -eq 1 ]]; then
  msg="Blocked: staged shell scripts have errors (fix before committing):"$'\n'"$msgs"
  if [[ "$have_shellcheck" -eq 0 ]]; then
    msg+="  (shellcheck not installed — only syntax checked)"$'\n'
  fi
  if [[ "$is_agy" -eq 1 ]]; then
    python3 -c "import json, sys; print(json.dumps({'decision': 'deny', 'reason': sys.argv[1]}))" "$msg"
    exit 0
  else
    printf '%s' "$msg" >&2
    exit 2
  fi
fi

[[ "$is_agy" -eq 1 ]] && echo '{"decision": "allow"}'
exit 0
