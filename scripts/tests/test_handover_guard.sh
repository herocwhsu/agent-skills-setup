#!/usr/bin/env bash
# test_handover_guard.sh — templates/hooks/common/handover-guard.sh holds owner-run
# scripts in scripts/handover/ to their contract: a log file, no typed secret,
# a stated rollback, and a resume path backed by a marker file. Edit mode reads
# Claude's hook input; --all checks every handover script for a repo's init.sh.
# shellcheck disable=SC2016  # the sed patterns match literal $vars in the script under test
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$(cd "$SCRIPT_DIR/../templates/hooks/common" && pwd)/handover-guard.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

REPO="$TMPDIR/repo"
mkdir -p "$REPO/scripts/handover"
git -C "$REPO" init -q

compliant() {
  cat <<'EOF'
#!/usr/bin/env bash
# demo.sh — owner-run handover.
# Resume: rerun the same command; a passed host is skipped.
# Rollback: git revert abc123 restores the old playbook.
set -euo pipefail
log="$HOME/logs/demo-$(date +%s).log"
done_file="$HOME/logs/demo.done"
if [[ -f "$done_file" ]]; then echo done; exit 0; fi
ansible-playbook site.yml --become-password-file "$HOME/.pw" 2>&1 | tee -a "$log"
date > "$done_file"
EOF
}

edit() { # <file> -> "<exit> <stderr>"
  local err rc
  err=$(cd "$REPO" && printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
  echo "$rc $err"
}

case_blocks() { # <name> <file> <expected stderr fragment>
  local r; r=$(edit "$2")
  if [[ "${r%% *}" == 2 && "$r" == *"$3"* ]]; then ok "$1"; else bad "$1" "want exit 2 naming '$3', got: $r"; fi
}

F="$REPO/scripts/handover/demo.sh"

compliant > "$F"
r=$(edit "$F")
if [[ "${r%% *}" == 0 ]]; then ok "a compliant handover script passes"; else bad "a compliant handover script passes" "$r"; fi

compliant | sed 's|--become-password-file "$HOME/.pw"|-K|' > "$F"
case_blocks "ansible -K is blocked" "$F" "typed secret"
compliant | sed 's|--become-password-file "$HOME/.pw"|--ask-become-pass|' > "$F"
case_blocks "--ask-become-pass is blocked" "$F" "typed secret"
{ compliant; echo 'read -r -s -p "sudo: " pw'; } > "$F"
case_blocks "read -s is blocked" "$F" "typed secret"

compliant | sed 's/ | tee -a "$log"//' > "$F"
case_blocks "no log file is blocked" "$F" "log file"

compliant | grep -v '^# Rollback:' > "$F"
case_blocks "no Rollback header is blocked" "$F" "Rollback"
compliant | sed 's/^# Rollback:.*/# Rollback:/' > "$F"
case_blocks "an empty Rollback header is blocked" "$F" "Rollback"

compliant | grep -v '^# Resume:' > "$F"
case_blocks "no Resume header is blocked" "$F" "Resume"
compliant | grep -v 'done_file' > "$F"
case_blocks "no marker file is blocked" "$F" "marker file"

# Other spellings of a typed secret (review of 2026-10-24).
for line in 'ansible-playbook site.yml -bK' 'ansible-playbook site.yml -kK' \
            'ansible-playbook site.yml "-K"' 'opts=(--become -K)' \
            'ansible-playbook site.yml -k' 'ansible-playbook site.yml --ask-vault-pass' \
            'ANSIBLE_BECOME_ASK_PASS=True ansible-playbook site.yml' \
            'read -p "Password: " -s pw' 'echo "step #2"; ansible-playbook site.yml -K' \
            'read -s pw' 'read -sp "Password: " pw' 'IFS= read -rs pw' \
            'sudo -K && ansible-playbook site.yml -K' \
            'ansible-playbook -CK site.yml' 'ansible-playbook site.yml -DK' \
            'ansible-playbook -i inv site.yml -K; rc=$?' 'ansible-playbook site.yml -K&& echo ok' \
            'ansible-playbook site.yml -J'; do
  { compliant; echo "$line"; } > "$F"
  case_blocks "typed secret blocked: $line" "$F" "typed secret"
done
for line in 'sudo -K' 'curl -K "$HOME/.curlrc" https://example.com' 'rm -rf "$tmp"' \
            'kill -KILL "$pid"' 'pkill -SIGKILL -f myapp' 'read -r kb _ < <(du -sk "$dir")' \
            'curl -fsS -K "$cfg" https://example.com'; do
  { compliant; echo "$line"; } > "$F"
  r=$(edit "$F")
  if [[ "${r%% *}" == 0 ]]; then ok "not a typed secret: $line"; else bad "not a typed secret: $line" "$r"; fi
done

# A '>' inside a string is not a log.
compliant | sed 's/ | tee -a "$log"//' > "$F"; echo 'echo "==> logging in"' >> "$F"
case_blocks "an arrow before 'logging' is not a log file" "$F" "log file"
# The log is appended on every run, so it cannot be the resume marker.
compliant | grep -v 'done_file' > "$F"; echo '[[ -f "$log" ]] || echo new; date >> "$log"' >> "$F"
case_blocks "the log file is not a marker file" "$F" "marker file"
# rm -f is not a test of the file.
compliant | grep -v 'done_file' > "$F"; printf '%s\n' 'tmp=$(mktemp)' 'rm -f "$tmp"' 'date > "$tmp"' >> "$F"
case_blocks "rm -f is not a marker test" "$F" "marker file"
# hangar's form: a negated test inside a compound one.
compliant | sed 's/if \[\[ -f "$done_file" \]\]/if [[ -n "$x" \&\& ! -f "$done_file" ]]/' > "$F"
r=$(edit "$F")
if [[ "${r%% *}" == 0 ]]; then ok "a negated test in a compound [[ ]] is a marker test"; else bad "a negated test in a compound [[ ]] is a marker test" "$r"; fi
for t in '[ -n "$x" -a -f "$done_file" ]' '[ -f "$x" -o -f "$done_file" ]' '[[ -n "$x" && ( -f "$done_file" ) ]]'; do
  compliant | sed "s/if \[\[ -f \"\$done_file\" \]\]/if ${t//&/\\&}/" > "$F"
  grep -qF "if $t" "$F" || bad "marker test form: $t" "sed did not plant it"
  r=$(edit "$F")
  if [[ "${r%% *}" == 0 ]]; then ok "marker test form: $t"; else bad "marker test form: $t" "$r"; fi
done

# Comments may name the forbidden flag, as hangar's header does ("never -K").
{ compliant | head -2; echo '# Sudo comes from a file, never -K.'; compliant | tail -n +3; } > "$F"
r=$(edit "$F")
if [[ "${r%% *}" == 0 ]]; then ok "-K in a comment is allowed"; else bad "-K in a comment is allowed" "$r"; fi

# Files outside scripts/handover/ and non-shell files are not checked.
echo 'sudo -K' > "$REPO/scripts/other.sh"
r=$(edit "$REPO/scripts/other.sh")
if [[ "${r%% *}" == 0 ]]; then ok "a script outside scripts/handover/ is ignored"; else bad "a script outside scripts/handover/ is ignored" "$r"; fi
echo 'notes -K' > "$REPO/scripts/handover/README.md"
r=$(edit "$REPO/scripts/handover/README.md")
if [[ "${r%% *}" == 0 ]]; then ok "a non-.sh file in scripts/handover/ is ignored"; else bad "a non-.sh file in scripts/handover/ is ignored" "$r"; fi

r=$(cd "$REPO" && printf 'not json' | bash "$GUARD" 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then ok "unparseable input fails open"; else bad "unparseable input fails open" "exit $rc: $r"; fi

# --all: whole-repo mode for init.sh, from any directory inside the repo.
compliant > "$F"
compliant > "$REPO/scripts/handover/second.sh"
out=$(cd "$REPO/scripts" && bash "$GUARD" --all 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then ok "--all passes when every script complies"; else bad "--all passes when every script complies" "exit $rc: $out"; fi
compliant | sed 's|--become-password-file "$HOME/.pw"|-K|' > "$REPO/scripts/handover/second.sh"
out=$(cd "$REPO/scripts" && bash "$GUARD" --all 2>&1); rc=$?
if [[ $rc -eq 2 && "$out" == *"second.sh"* && "$out" != *"demo.sh"* ]]; then
  ok "--all blocks and names only the failing script"
else
  bad "--all blocks and names only the failing script" "exit $rc: $out"
fi
compliant > "$REPO/scripts/handover/second.sh"
mkdir -p "$REPO/scripts/handover/sub"
compliant | sed 's|--become-password-file "$HOME/.pw"|-K|' > "$REPO/scripts/handover/sub/nested.sh"
out=$(cd "$REPO" && bash "$GUARD" --all 2>&1); rc=$?
if [[ $rc -eq 2 && "$out" == *"nested.sh"* ]]; then
  ok "--all checks scripts in subdirectories, as edit mode does"
else
  bad "--all checks scripts in subdirectories, as edit mode does" "exit $rc: $out"
fi
rm -rf "$REPO/scripts/handover"
out=$(cd "$REPO" && bash "$GUARD" --all 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then ok "--all passes a repo without scripts/handover/"; else bad "--all passes a repo without scripts/handover/" "exit $rc: $out"; fi

echo "handover-guard: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
