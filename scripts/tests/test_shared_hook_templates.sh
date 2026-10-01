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
HOOKS_SRC="$(cd "$SCRIPT_DIR/../hooks" && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

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

LOGSTUB="$TMPDIR/logstub"; mkdir -p "$LOGSTUB"
# shellcheck disable=SC2016  # the stub's own $* and $(pwd) must stay unexpanded
printf '#!/usr/bin/env bash\necho "ARGS: $*" > "%s/args"\necho "CWD: $(pwd -P)" >> "%s/args"\nexit 0\n' "$LOGSTUB" "$LOGSTUB" > "$LOGSTUB/gitleaks"
chmod +x "$LOGSTUB/gitleaks"
( cd "$DIRTY" && printf '{}' | PATH="$LOGSTUB:$PATH" bash "$HOOKS_SRC/common/secret-scan.sh" ) >/dev/null 2>&1
if grep -q -- '--source \.' "$LOGSTUB/args" 2>/dev/null \
   && grep -q "CWD: $(cd "$DIRTY" && pwd -P)\$" "$LOGSTUB/args"; then
  ok "secret-scan runs gitleaks as --source . from the repo root"
else
  bad "secret-scan runs gitleaks as --source . from the repo root" "got: $(tr '\n' ' ' < "$LOGSTUB/args" 2>/dev/null)"
fi

echo ""
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
