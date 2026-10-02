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
classify=$(printf '%s' "$input" | python3 -c "
import json, os, shlex, subprocess, sys
try:
    d = json.load(sys.stdin)
    cmd = (
        d.get('tool_input', {}).get('command')
        or d.get('toolCall', {}).get('args', {}).get('CommandLine')
        or ''
    )
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    toks = list(lex)
except Exception:
    sys.exit(0)  # unparseable -> skip (fail open)

# Split on shell control operators (&&, ||, ;, |, &, parens) so a commit
# chained after another command -- 'git add x && git commit' -- is still
# seen. punctuation_chars keeps operators inside a quoted -m message as part
# of that one token.
segs, cur = [], []
for t in toks:
    if t and all(c in '();<>|&' for c in t):
        segs.append(cur); cur = []
    else:
        cur.append(t)
segs.append(cur)

def ls_files(cdir, args, specs):
    try:
        r = subprocess.run(['git', '-C', cdir, 'ls-files', '-z'] + args + ['--'] + specs,
                           capture_output=True, text=True, check=False)
    except Exception:
        return []
    return [os.path.normpath(os.path.join(cdir, f)) for f in r.stdout.split(chr(0)) if f]

# The hook runs BEFORE the command, so files the command itself stages
# (git add ... && git commit, git commit -a) are not in the index yet. Collect
# them from the working tree; live AGY and Codex runs committed a broken
# script exactly this way.
pending = []
for seg in segs:
    for i, t in enumerate(seg):
        if t != 'git':
            continue
        cdir = '.'
        j = i + 1
        while j < len(seg):
            t2 = seg[j]
            if t2 == '-C' and j + 1 < len(seg):
                cdir = os.path.join(cdir, seg[j + 1]); j += 2; continue
            if t2 == '-c':
                j += 2; continue
            if t2.startswith('-'):
                j += 1; continue
            break
        if j >= len(seg):
            continue
        sub, rest = seg[j], seg[j + 1:]
        if sub == 'add':
            specs, mode = [], ''
            for k, x in enumerate(rest):
                if x == '--':
                    specs += rest[k + 1:]; break
                if x in ('-A', '--all'):
                    mode = 'all'
                elif x in ('-u', '--update'):
                    mode = mode or 'update'
                elif not x.startswith('-'):
                    specs.append(x)
            if mode == 'update':
                pending += ls_files(cdir, ['-m'], specs)
            elif mode == 'all' or specs:
                pending += ls_files(cdir, ['-m', '-o', '--exclude-standard'], specs)
        elif sub == 'commit':
            if '--dry-run' in rest or '--help' in rest or '-h' in rest:
                continue  # not a real committing invocation
            k = 0
            while k < len(rest):
                x = rest[k]
                if x == '--all':
                    pending += ls_files(cdir, ['-m'], [])
                elif x.startswith('-') and not x.startswith('--') and len(x) > 1:
                    for ch in x[1:]:
                        if ch == 'a':
                            pending += ls_files(cdir, ['-m'], [])
                        if ch in 'mFcCt':
                            if ch == x[-1]:
                                k += 1  # the option's value is the next token
                            break
                k += 1
            print('GATE')
            for f in dict.fromkeys(pending):
                print('WT ' + f)
            sys.exit(0)
" 2>/dev/null)
decision=${classify%%$'\n'*}

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

# Portable (bash 3.2 / macOS /bin/bash has no mapfile).
wt=()
while IFS= read -r l; do
  [[ "$l" == "WT "*.sh ]] && wt+=("${l#WT }")
done <<< "$classify"

staged=()
while IFS= read -r f; do
  [[ -n "$f" ]] && staged+=("$f")
done < <(git diff --cached --name-only --diff-filter=ACM | grep -E '\.sh$' || true)
if [[ ${#staged[@]} -eq 0 && ${#wt[@]} -eq 0 ]]; then
  [[ "$is_agy" -eq 1 ]] && echo '{"decision": "allow"}'
  exit 0
fi

have_shellcheck=0
command -v shellcheck >/dev/null 2>&1 && have_shellcheck=1

scratch=$(mktemp)
trap 'rm -f "$scratch"' EXIT
fail=0
msgs=""
check_content() {  # <file> <content>
  if ! printf '%s' "$2" | bash -n - 2>"$scratch"; then
    fail=1; msgs+="  $1: bash syntax error"$'\n'
  elif [[ "$have_shellcheck" -eq 1 ]]; then
    if ! printf '%s' "$2" | shellcheck --severity=error - >"$scratch" 2>&1; then
      fail=1; msgs+="  $1: shellcheck error"$'\n'
    fi
  fi
}
for f in ${staged[@]+"${staged[@]}"}; do
  restaged=0
  for w in ${wt[@]+"${wt[@]}"}; do [[ "$w" == "$f" ]] && restaged=1; done
  [[ "$restaged" -eq 1 ]] && continue  # the command re-stages it; check the working tree copy
  blob=$(git show ":$f" 2>/dev/null) || continue
  check_content "$f" "$blob"
done
for f in ${wt[@]+"${wt[@]}"}; do
  [[ -f "$f" ]] || continue
  check_content "$f" "$(cat "$f")"
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
