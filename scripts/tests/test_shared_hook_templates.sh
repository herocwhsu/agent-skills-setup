#!/usr/bin/env bash
# test_shared_hook_templates.sh — the five hook templates shared with the hangar
# and atelier repos (secret-scan, semgrep-guard, checkov-guard, placeholder-guard,
# sh-check) must keep the behaviour those repos depend on: a Stop hook gates on
# turn scope, and a PostToolUse hook blocks with exit 2 on stderr.
#
# Scanners are stubbed on PATH. Without stubs a hook on a machine lacking the tool
# prints "SKIP ... not installed" and exits 0, so a gate assertion would pass
# without ever reaching the gate. The failing stub exits 1, so a hook that really
# invoked its tool must block (exit 2) and one that gated itself off exits 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_SRC="$(cd "$SCRIPT_DIR/../templates/hooks" && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }
expect() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1" "want exit $2, got $3"; fi
}

STUBS="$TMPDIR/stubs"; mkdir -p "$STUBS"
for t in semgrep checkov gitleaks osv-scanner; do
  printf '#!/usr/bin/env bash\necho STUB-RAN-%s >&2\nexit 1\n' "$t" > "$STUBS/$t"
  chmod +x "$STUBS/$t"
done

repo() {
  local d="$TMPDIR/$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" -c user.email=t@example.com -c user.name=test commit -q --allow-empty -m init
  echo "$d"
}

stop_hook() { # <template> <repo>  -> prints "<exit> <stdout>"
  local out rc
  out=$(cd "$2" && printf '{}' | PATH="$STUBS:$PATH" bash "$HOOKS_SRC/$1" 2>/dev/null); rc=$?
  echo "$rc $out"
}

edit_hook() { # <template> <repo> <file>  -> prints exit code
  ( cd "$2" && printf '{"tool_input":{"file_path":"%s"}}' "$3" | bash "$HOOKS_SRC/$1" >/dev/null 2>&1 )
  echo $?
}

CLEAN=$(repo clean)
DIRTY=$(repo dirty)
printf 'a: 1\n' > "$DIRTY/t.yaml"
printf 'x = 1\n' > "$DIRTY/a.py"

for h in common/semgrep-guard.sh k8s/checkov-guard.sh common/secret-scan.sh; do
  b=$(basename "$h")
  r=$(stop_hook "$h" "$CLEAN")
  if [[ "${r%% *}" == 0 && "$r" == *"turn changed nothing"* ]]; then
    ok "$b skips a turn that changed nothing"
  else
    bad "$b skips a turn that changed nothing" "got: $r"
  fi
  r=$(stop_hook "$h" "$DIRTY")
  if [[ "${r%% *}" == 2 ]]; then
    ok "$b runs its tool, and blocks, when the turn changed in-scope files"
  else
    bad "$b runs its tool when the turn changed in-scope files" "got: $r"
  fi
done

printf 'if then fi\n' > "$DIRTY/bad.sh"
printf '#!/usr/bin/env bash\necho ok\n' > "$DIRTY/good.sh"
if [[ "$(edit_hook common/sh-check.sh "$DIRTY" "$DIRTY/bad.sh")" == 2 ]]; then
  ok "sh-check blocks a syntax error with exit 2"
else
  bad "sh-check blocks a syntax error with exit 2" "did not exit 2"
fi
if [[ "$(edit_hook common/sh-check.sh "$DIRTY" "$DIRTY/good.sh")" == 0 ]]; then
  ok "sh-check allows a clean script"
else
  bad "sh-check allows a clean script" "did not exit 0"
fi
# Exercise the shellcheck step itself, not just bash -n: a failing stub on PATH must block a
# syntactically valid script, and a passing one must not.
SC="$TMPDIR/shellcheck-stub"; mkdir -p "$SC"
printf '#!/usr/bin/env bash\necho "SC2086: unquoted" >&2\nexit 1\n' > "$SC/shellcheck"; chmod +x "$SC/shellcheck"
r=$( ( cd "$DIRTY" && printf '{"tool_input":{"file_path":"%s"}}' "$DIRTY/good.sh" | PATH="$SC:$PATH" bash "$HOOKS_SRC/common/sh-check.sh" ) >/dev/null 2>&1; echo $? )
if [[ "$r" == 2 ]]; then ok "sh-check blocks on a shellcheck finding"; else bad "sh-check blocks on a shellcheck finding" "got exit $r"; fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$SC/shellcheck"
r=$( ( cd "$DIRTY" && printf '{"tool_input":{"file_path":"%s"}}' "$DIRTY/good.sh" | PATH="$SC:$PATH" bash "$HOOKS_SRC/common/sh-check.sh" ) >/dev/null 2>&1; echo $? )
if [[ "$r" == 0 ]]; then ok "sh-check allows a clean shellcheck run"; else bad "sh-check allows a clean shellcheck run" "got exit $r"; fi

printf 'host: 10.1.2.3\n' > "$DIRTY/ip.yaml"
printf 'host: <DB_HOST>\n' > "$DIRTY/ok.yaml"
if [[ "$(edit_hook k8s/placeholder-guard.sh "$DIRTY" "$DIRTY/ip.yaml")" == 2 ]]; then
  ok "placeholder-guard blocks an added hardcoded IP"
else
  bad "placeholder-guard blocks an added hardcoded IP" "did not exit 2"
fi
if [[ "$(edit_hook k8s/placeholder-guard.sh "$DIRTY" "$DIRTY/ok.yaml")" == 0 ]]; then
  ok "placeholder-guard allows a placeholder"
else
  bad "placeholder-guard allows a placeholder" "did not exit 0"
fi

# Committed but never pushed must open the gate too. The gate is measured against
# the merge-base with upstream, not HEAD; keyed on HEAD, a commit-then-stop session
# skips every scan.
UP="$TMPDIR/upstream.git"; CL="$TMPDIR/clone"
git init -q --bare "$UP"
git clone -q "$UP" "$CL" 2>/dev/null
git -C "$CL" -c user.email=t@example.com -c user.name=test commit -q --allow-empty -m init
git -C "$CL" push -q -u origin "$(git -C "$CL" rev-parse --abbrev-ref HEAD)" 2>/dev/null
printf 'a: 1\n' > "$CL/t.yaml"
git -C "$CL" add -A
git -C "$CL" -c user.email=t@example.com -c user.name=test commit -q -m work
for h in common/semgrep-guard.sh k8s/checkov-guard.sh common/secret-scan.sh; do
  r=$(stop_hook "$h" "$CL")
  if [[ "${r%% *}" == 2 ]]; then
    ok "$(basename "$h") opens its gate for a committed, unpushed change"
  else
    bad "$(basename "$h") opens its gate for a committed, unpushed change" "got: $r"
  fi
done

# placeholder-guard: a credential blocks, and a value already committed does not.
printf 'password: hunter2xyz\n' > "$DIRTY/cred.yaml"
if [[ "$(edit_hook k8s/placeholder-guard.sh "$DIRTY" "$DIRTY/cred.yaml")" == 2 ]]; then
  ok "placeholder-guard blocks an added credential"
else
  bad "placeholder-guard blocks an added credential" "did not exit 2"
fi
git -C "$DIRTY" add -A
git -C "$DIRTY" -c user.email=t@example.com -c user.name=test commit -q -m baseline
if [[ "$(edit_hook k8s/placeholder-guard.sh "$DIRTY" "$DIRTY/ip.yaml")" == 0 ]]; then
  ok "placeholder-guard ignores a value that was already committed"
else
  bad "placeholder-guard ignores a value that was already committed" "did not exit 0"
fi
printf 'note: hello\n' >> "$DIRTY/ip.yaml"
if [[ "$(edit_hook k8s/placeholder-guard.sh "$DIRTY" "$DIRTY/ip.yaml")" == 0 ]]; then
  ok "placeholder-guard ignores a benign edit to a file that already holds an IP"
else
  bad "placeholder-guard ignores a benign edit to a file that already holds an IP" "did not exit 0"
fi
printf 'other: 10.9.9.9\n' >> "$DIRTY/ok.yaml"
if [[ "$(edit_hook k8s/placeholder-guard.sh "$DIRTY" "$DIRTY/ok.yaml")" == 2 ]]; then
  ok "placeholder-guard blocks an IP added to an already committed file"
else
  bad "placeholder-guard blocks an IP added to an already committed file" "did not exit 2"
fi

LOGSTUB="$TMPDIR/logstub"; mkdir -p "$LOGSTUB"
# shellcheck disable=SC2016  # the stub's own $* and $(pwd) must stay unexpanded
printf '#!/usr/bin/env bash\necho "ARGS: $*" > "%s/args"\necho "FILES: $(find . -type f | sort | tr "\\n" " ")" >> "%s/args"\nexit 0\n' "$LOGSTUB" "$LOGSTUB" > "$LOGSTUB/gitleaks"
chmod +x "$LOGSTUB/gitleaks"
GL=$(repo gitleaks-args)
printf 'a: 1\n' > "$GL/t.yaml"
printf 'out/\n' > "$GL/.gitignore"
mkdir -p "$GL/out"; printf 'b: 2\n' > "$GL/out/x.yaml"
( cd "$GL" && printf '{}' | PATH="$LOGSTUB:$PATH" bash "$HOOKS_SRC/common/secret-scan.sh" ) >/dev/null 2>&1
if grep -q -- '--source \.' "$LOGSTUB/args" 2>/dev/null \
   && grep -qx 'FILES: ./.gitignore ./t.yaml ' "$LOGSTUB/args"; then
  ok "secret-scan runs gitleaks as --source . over only the files git would commit"
else
  bad "secret-scan runs gitleaks as --source . over only the files git would commit" "got: $(tr '\n' ' ' < "$LOGSTUB/args" 2>/dev/null)"
fi

# With the real gitleaks: findings follow what git would commit, and a committed
# .gitleaksignore entry (file:rule:line, repo-relative) still matches.
if command -v gitleaks >/dev/null 2>&1; then
  token() { printf 'tok = "ghp_%s"\n' "$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"; }
  scan_rc() { ( cd "$1" && printf '{}' | bash "$HOOKS_SRC/common/secret-scan.sh" >/dev/null 2>&1 ); echo $?; }
  leak_repo() { local d; d=$(repo "$1"); printf 'build/\n' > "$d/.gitignore"; mkdir -p "$d/build"; echo "$d"; }

  R=$(leak_repo leak-ignored); token > "$R/build/out.txt"
  expect "secret-scan ignores a token in a gitignored file" 0 "$(scan_rc "$R")"
  R=$(leak_repo leak-untracked); token > "$R/new.py"
  expect "secret-scan finds a token in an untracked, not ignored file" 2 "$(scan_rc "$R")"
  R=$(leak_repo leak-tracked); token > "$R/a.py"
  git -C "$R" add -A; git -C "$R" -c user.email=t@example.com -c user.name=test commit -q -m t
  printf 'x\n' > "$R/other.txt"
  expect "secret-scan finds a token in a tracked file" 2 "$(scan_rc "$R")"
  printf 'a.py:github-pat:1\n' > "$R/.gitleaksignore"
  expect "secret-scan honours a .gitleaksignore file:rule:line entry" 0 "$(scan_rc "$R")"
  rm -f "$R/a.py" "$R/.gitleaksignore"
  expect "secret-scan skips a tracked file deleted from the working tree" 0 "$(scan_rc "$R")"
  R=$(leak_repo leak-space); token > "$R/my file.py"
  expect "secret-scan scans a file whose name has a space" 2 "$(scan_rc "$R")"
  # A file the copy cannot read must not end the hook before gitleaks runs:
  # the token in the readable file is still reported, and the gap is named.
  if [[ $(id -u) -ne 0 ]]; then
    R=$(leak_repo leak-unreadable); token > "$R/b.py"; printf 'x\n' > "$R/c.txt"; chmod 000 "$R/c.txt"
    err=$( cd "$R" && printf '{}' | bash "$HOOKS_SRC/common/secret-scan.sh" 2>&1 >/dev/null ); rc=$?
    chmod 600 "$R/c.txt"
    if [[ $rc -eq 2 && "$err" == *"gitleaks found"* && "$err" == *"not scanned"* ]]; then
      ok "secret-scan still scans, and warns, when a file cannot be copied"
    else
      bad "secret-scan still scans, and warns, when a file cannot be copied" "rc=$rc err=$err"
    fi
  fi
  # No temp folder for the copy (full or unwritable temp volume): the hook falls
  # back to scanning the tree in place rather than ending before gitleaks runs.
  NOTMP="$TMPDIR/notmp"; mkdir -p "$NOTMP"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$NOTMP/mktemp"; chmod +x "$NOTMP/mktemp"
  R=$(leak_repo leak-notmp); token > "$R/a.py"
  rc=$( cd "$R" && printf '{}' | PATH="$NOTMP:$PATH" bash "$HOOKS_SRC/common/secret-scan.sh" >/dev/null 2>&1; echo $? )
  expect "secret-scan scans the tree in place when no temp folder can be made" 2 "$rc"
else
  echo "  SKIP  real-gitleaks secret-scan cases: gitleaks not installed"
fi

# py-guard / ts-guard: gate on the app folders in APP_DIRS whose files changed
# against the upstream merge-base. Failing stubs for every tool they call: a hook
# that opened its gate blocks (exit 2), one that gated itself off exits 0.
TOOLS="$TMPDIR/tools"; mkdir -p "$TOOLS"
for t in ruff bandit pip-audit pytest node npm npx; do
  printf '#!/usr/bin/env bash\necho STUB-FAIL-%s\nexit 1\n' "$t" > "$TOOLS/$t"; chmod +x "$TOOLS/$t"
done
# Only what the hooks need besides the tools, so a tool installed on this machine
# can't stand in for a missing one.
MINPATH="$TMPDIR/minpath"; mkdir -p "$MINPATH"
for t in bash git grep sort head tail cat dirname env; do ln -sf "$(command -v "$t")" "$MINPATH/$t"; done

configured() { # <template> <app dirs, e.g. '"apps/api"'> -> path of a configured copy
  local out; out="$TMPDIR/cfg-$(basename "$1" .sh)-$RANDOM.sh"
  sed "s|^APP_DIRS=.*|APP_DIRS=($2)|" "$HOOKS_SRC/$1" > "$out"
  echo "$out"
}

app_repo() { # <file> [file...] -> clone with these files committed and pushed
  local up cl f
  up=$(mktemp -d "$TMPDIR/up.XXXX"); cl=$(mktemp -d "$TMPDIR/cl.XXXX")
  git -C "$up" init -q --bare
  git clone -q "$up" "$cl/w" 2>/dev/null
  for f in "$@"; do mkdir -p "$(dirname "$cl/w/$f")"; printf 'x = 1\n' > "$cl/w/$f"; done
  printf '{}\n' > "$cl/w/tsconfig.json"; mkdir -p "$cl/w/apps/web"; printf '{}\n' > "$cl/w/apps/web/tsconfig.json"
  git -C "$cl/w" add -A
  git -C "$cl/w" -c user.email=t@example.com -c user.name=test commit -q -m init
  git -C "$cl/w" push -q -u origin "$(git -C "$cl/w" rev-parse --abbrev-ref HEAD)" 2>/dev/null
  echo "$cl/w"
}

guard_rc() { # <hook path> <repo> [PATH] -> exit code
  ( cd "$2" && printf '{}' | PATH="${3:-$TOOLS:$PATH}" bash "$1" >/dev/null 2>&1 ); echo $?
}

for spec in "python/py-guard.sh:src/a.py:src/b.py:apps/api/src/a.py:apps/other/a.py:\"apps/api\"" \
            "js/ts-guard.sh:src/a.ts:src/b.ts:apps/web/src/a.ts:apps/other/src/a.ts:\"apps/web\""; do
  IFS=: read -r h tracked fresh app_file other_file dirs <<< "$spec"
  b=$(basename "$h")
  W=$(app_repo "$tracked")
  expect "$b (APP_DIRS=.) exits 0 when nothing changed" 0 "$(guard_rc "$HOOKS_SRC/$h" "$W")"
  printf '# edit\n' >> "$W/$tracked"
  expect "$b (APP_DIRS=.) blocks on a tracked edit" 2 "$(guard_rc "$HOOKS_SRC/$h" "$W")"
  W=$(app_repo "$tracked"); printf '# new\n' > "$W/$fresh"
  expect "$b (APP_DIRS=.) blocks on an untracked file" 2 "$(guard_rc "$HOOKS_SRC/$h" "$W")"
  W=$(app_repo "$tracked"); printf '# edit\n' >> "$W/$tracked"
  git -C "$W" -c user.email=t@example.com -c user.name=test commit -qam work
  expect "$b (APP_DIRS=.) blocks on a committed but unpushed edit" 2 "$(guard_rc "$HOOKS_SRC/$h" "$W")"

  cfg=$(configured "$h" "$dirs")
  W=$(app_repo "$app_file" "$other_file"); printf '# edit\n' >> "$W/$other_file"
  expect "$b (APP_DIRS=$dirs) ignores a change outside its folders" 0 "$(guard_rc "$cfg" "$W")"
  printf '# edit\n' >> "$W/$app_file"
  expect "$b (APP_DIRS=$dirs) blocks on a change in its folder" 2 "$(guard_rc "$cfg" "$W")"

  W=$(app_repo "$tracked"); printf '# edit\n' >> "$W/$tracked"
  out=$( cd "$W" && printf '{}' | PATH="$MINPATH" bash "$HOOKS_SRC/$h" 2>&1 ); rc=$?
  if [[ $rc -eq 0 && "$out" == *SKIP* ]]; then
    ok "$b says SKIP and does not block when its tools are missing"
  else
    bad "$b says SKIP and does not block when its tools are missing" "exit $rc: $out"
  fi
done

W=$(app_repo src/a.py); printf '# edit\n' >> "$W/src/a.py"
out=$( cd "$W" && printf '{}' | PATH="$TOOLS:$PATH" bash "$HOOKS_SRC/python/py-guard.sh" 2>&1 >/dev/null )
if [[ "$out" == *STUB-FAIL-ruff* ]]; then
  ok "py-guard shows the failing tool's output"
else
  bad "py-guard shows the failing tool's output" "stderr: $out"
fi

# pip-audit 2.10 has no -q (exit 2, "unrecognized arguments"), which read as
# vulnerable deps on every run. Passing stubs, and a pip-audit that rejects -q.
OKTOOLS="$TMPDIR/oktools"; mkdir -p "$OKTOOLS"
for t in ruff bandit pytest; do printf '#!/usr/bin/env bash\nexit 0\n' > "$OKTOOLS/$t"; chmod +x "$OKTOOLS/$t"; done
cat > "$OKTOOLS/pip-audit" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do [[ "$a" == -q ]] && { echo "pip-audit: error: unrecognized arguments: -q" >&2; exit 2; }; done
exit 0
STUB
chmod +x "$OKTOOLS/pip-audit"
W=$(app_repo src/a.py); printf 'certifi==1\n' > "$W/requirements.txt"; printf '# edit\n' >> "$W/src/a.py"
expect "py-guard runs pip-audit with flags it accepts" 0 "$(guard_rc "$HOOKS_SRC/python/py-guard.sh" "$W" "$OKTOOLS:$PATH")"
# pip-audit exits 1 for findings and for failures alike: only findings block; a
# run that could not audit (offline, unresolvable) says SKIP.
FAILTOOLS="$TMPDIR/failtools"; mkdir -p "$FAILTOOLS"; cp "$OKTOOLS"/* "$FAILTOOLS/"
printf '#!/usr/bin/env bash\necho "ERROR: No matching distribution found for nopkg==1.0" >&2\necho "ERROR:pip_audit._cli:Failed to install packages: [/tmp/x]" >&2\nexit 1\n' > "$FAILTOOLS/pip-audit"
out=$( cd "$W" && printf '{}' | PATH="$FAILTOOLS:$PATH" bash "$HOOKS_SRC/python/py-guard.sh" 2>&1 ); rc=$?
if [[ $rc -eq 0 && "$out" == *"SKIP  pip-audit could not run: ERROR: No matching distribution found for nopkg==1.0"* ]]; then ok "py-guard says SKIP when pip-audit cannot run"; else bad "py-guard says SKIP when pip-audit cannot run" "exit $rc: $out"; fi
printf '#!/usr/bin/env bash\necho "Found 1 known vulnerability in 1 package"\nexit 1\n' > "$FAILTOOLS/pip-audit"
expect "py-guard blocks on a pip-audit finding" 2 "$(guard_rc "$HOOKS_SRC/python/py-guard.sh" "$W" "$FAILTOOLS:$PATH")"

# ESLint 9 with a flat config rejects `-q` (exit 2) and only takes --quiet.
ESL="$TMPDIR/eslint9"; mkdir -p "$ESL"
for t in node npm; do printf '#!/usr/bin/env bash\nexit 0\n' > "$ESL/$t"; chmod +x "$ESL/$t"; done
# shellcheck disable=SC2016  # $a expands inside the stub, not here
printf '#!/usr/bin/env bash\nfor a; do [[ "$a" == -q ]] && { echo "Invalid option -q"; exit 2; }; done\nexit 0\n' > "$ESL/npx"; chmod +x "$ESL/npx"
W=$(app_repo src/a.ts); printf 'export default []\n' > "$W/eslint.config.js"; printf '// edit\n' >> "$W/src/a.ts"
expect "ts-guard passes when eslint 9 (flat config) finds nothing" 0 "$(guard_rc "$HOOKS_SRC/js/ts-guard.sh" "$W" "$ESL:$PATH")"

# ts-fix: the prettier of the APP_DIRS folder that holds the file, nothing outside.
prettier_stub() { # <dir> : a prettier that records the file it was given
  mkdir -p "$1/node_modules/.bin"
  # shellcheck disable=SC2016  # the stub's own $@ and $f must stay unexpanded
  printf '#!/usr/bin/env bash\nfor a in "$@"; do f="$a"; done\necho "$f" >> "%s/prettier.log"\n' "$TMPDIR" \
    > "$1/node_modules/.bin/prettier"
  chmod +x "$1/node_modules/.bin/prettier"
}
TF=$(repo ts-fix); prettier_stub "$TF"; prettier_stub "$TF/apps/web"
mkdir -p "$TF/apps/web/src" "$TF/apps/other"
printf 'x\n' > "$TF/a.ts"; printf 'x\n' > "$TF/apps/web/src/a.ts"; printf 'x\n' > "$TF/apps/other/a.ts"
rm -f "$TMPDIR/prettier.log"
edit_hook js/ts-fix.sh "$TF" "$TF/a.ts" >/dev/null
if grep -qx "$TF/a.ts" "$TMPDIR/prettier.log" 2>/dev/null; then
  ok "ts-fix (APP_DIRS=.) formats a file with the root prettier"
else
  bad "ts-fix (APP_DIRS=.) formats a file with the root prettier" "log: $(cat "$TMPDIR/prettier.log" 2>/dev/null)"
fi
cfg=$(configured js/ts-fix.sh '"apps/web"')
rm -f "$TMPDIR/prettier.log"
( cd "$TF" && printf '{"tool_input":{"file_path":"%s"}}' "$TF/apps/web/src/a.ts" | bash "$cfg" >/dev/null 2>&1 )
( cd "$TF" && printf '{"tool_input":{"file_path":"%s"}}' "$TF/apps/other/a.ts" | bash "$cfg" >/dev/null 2>&1 )
if [[ "$(cat "$TMPDIR/prettier.log" 2>/dev/null)" == "$TF/apps/web/src/a.ts" ]]; then
  ok "ts-fix (APP_DIRS=apps/web) formats only files in that folder"
else
  bad "ts-fix (APP_DIRS=apps/web) formats only files in that folder" "log: $(cat "$TMPDIR/prettier.log" 2>/dev/null)"
fi

# harness-drift: blocks an edit that makes a template hook differ from its
# template outside the repo config block; quiet without an installed harness.
HD="$TMPDIR/hd"; HDH="$HD/home"; HDS="$HD/harness"; HDR=$(repo hd-repo)
mkdir -p "$HDH/.agent-skills-setup" "$HDS/scripts" "$HDS/templates/hooks/common" "$HDR/.claude/hooks"
cp "$SCRIPT_DIR/harness_adapter.py" "$SCRIPT_DIR/repo_audit.py" "$HDS/scripts/"
printf '#!/bin/bash\n# --- repo config ----------------------------------------\nV=""\n# --------------------------------------------------------\necho a\n' > "$HDS/templates/hooks/common/x.sh"
sed 's/^V=""/V="mine"/' "$HDS/templates/hooks/common/x.sh" > "$HDR/.claude/hooks/x.sh"
printf '{"schema_version":1,"harness":{"source":"agent-skills-setup","version":"x"},"project":{"name":"r"},"state_files":[],"verify":["true"],"hooks":[{"template":"common/x.sh","event":"edit"}]}\n' > "$HDR/agent-harness.json"
printf '{"commit":"x","source_dir":"%s"}\n' "$HDS" > "$HDH/.agent-skills-setup/harness-version.json"
hd_rc() { ( cd "$HDR" && printf '{"tool_input":{"file_path":"%s"}}' "$1" | HOME="$HDH" bash "$HOOKS_SRC/common/harness-drift.sh" >/dev/null 2>"$TMPDIR/hd.err" ); echo $?; }
expect "harness-drift allows an edit inside the config block" 0 "$(hd_rc "$HDR/.claude/hooks/x.sh")"
printf 'echo extra\n' >> "$HDR/.claude/hooks/x.sh"
expect "harness-drift blocks an edit that changes a template hook" 2 "$(hd_rc "$HDR/.claude/hooks/x.sh")"
if grep -q 'common/x.sh' "$TMPDIR/hd.err"; then ok "harness-drift names the template"; else bad "harness-drift names the template" "$(cat "$TMPDIR/hd.err")"; fi
printf 'x\n' > "$HDR/other.txt"
expect "harness-drift ignores other files" 0 "$(hd_rc "$HDR/other.txt")"
rm "$HDH/.agent-skills-setup/harness-version.json"
expect "harness-drift does nothing without an installed harness" 0 "$(hd_rc "$HDR/.claude/hooks/x.sh")"

echo ""
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
