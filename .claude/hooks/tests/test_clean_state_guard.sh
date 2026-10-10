#!/usr/bin/env bash
# Tests for .claude/hooks/clean-state-guard.sh (Clean-State Invariant 4 enforcement).
#
# Asserts exit code 2 on dirty workspace with 3-part diagnostic (WHAT + WHY + FIX)
# and exit 0 on clean workspace.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_DIR/.claude/hooks/clean-state-guard.sh"
[[ -f "$HOOK" ]] || { echo "FAIL: hook not found at $HOOK"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

run_hook() {
  local files="$1"
  CLEAN_STATE_GUARD_FILES="$files" bash "$HOOK" 2>&1
}

# --- 1. Clean workspace passes exit 0 ----------------------------------------
set +e; out=$(run_hook ""); status=$?; set -e
[[ $status -eq 0 ]] \
  && ok "empty/clean file list passes exit 0" \
  || bad "empty/clean file list passes exit 0" "exit $status, out: $out"

# --- 2. Normal source files pass exit 0 ---------------------------------------
normal_files=$'src/app.py\nscripts/build.sh\nREADME.md\nfeature_list.json'
set +e; out=$(run_hook "$normal_files"); status=$?; set -e
[[ $status -eq 0 ]] \
  && ok "normal source files pass exit 0" \
  || bad "normal source files pass exit 0" "exit $status, out: $out"

# --- 3. Scratch file blocks with exit 2 and 3-part diagnostic ------------------
dirty_scratch=$'src/app.py\nscratch.py'
set +e; out=$(run_hook "$dirty_scratch"); status=$?; set -e
[[ $status -eq 2 && "$out" =~ "WHAT:" && "$out" =~ "WHY:" && "$out" =~ "FIX:" && "$out" =~ "scratch.py" ]] \
  && ok "scratch.py blocks with exit 2 and 3-part diagnostic" \
  || bad "scratch.py blocks with exit 2 and 3-part diagnostic" "exit $status, out: $out"

# --- 4. WIP.md / IN_PROGRESS.md blocks exit 2 --------------------------------
dirty_wip=$'WIP.md\nIN_PROGRESS.md'
set +e; out=$(run_hook "$dirty_wip"); status=$?; set -e
[[ $status -eq 2 && "$out" =~ "WIP.md" ]] \
  && ok "WIP.md blocks with exit 2" \
  || bad "WIP.md blocks with exit 2" "exit $status, out: $out"

# --- 5. Backup and temporary extensions (*.tmp, *.bak, *.swp) block exit 2 ---
dirty_bak=$'file.bak\nsub/test.tmp\n.main.py.swp'
set +e; out=$(run_hook "$dirty_bak"); status=$?; set -e
[[ $status -eq 2 && "$out" =~ "file.bak" && "$out" =~ "test.tmp" ]] \
  && ok "backup and temp files (*.tmp, *.bak, *.swp) block exit 2" \
  || bad "backup and temp files (*.tmp, *.bak, *.swp) block exit 2" "exit $status, out: $out"

# --- 6. Environment secret file (.env, .env.local) blocks exit 2 --------------
dirty_env=$'.env\n.env.local'
set +e; out=$(run_hook "$dirty_env"); status=$?; set -e
[[ $status -eq 2 && "$out" =~ ".env" ]] \
  && ok ".env files block with exit 2" \
  || bad ".env files block with exit 2" "exit $status, out: $out"

# --- 7. Environment templates (.env.example) allowed exit 0 -------------------
safe_env=$'.env.example\n.env.template'
set +e; out=$(run_hook "$safe_env"); status=$?; set -e
[[ $status -eq 0 ]] \
  && ok ".env.example templates pass exit 0" \
  || bad ".env.example templates pass exit 0" "exit $status, out: $out"

# --- 8. Stray log in source tree blocks exit 2 -------------------------------
dirty_log=$'src/server.log\nscripts/debug.log'
set +e; out=$(run_hook "$dirty_log"); status=$?; set -e
[[ $status -eq 2 && "$out" =~ "server.log" ]] \
  && ok "stray debug log in source directory blocks exit 2" \
  || bad "stray debug log in source directory blocks exit 2" "exit $status, out: $out"

# --- 9. Log in ignored system path passes exit 0 ------------------------------
ignored_log=$'.system_generated/logs/transcript.log\n.venv/lib.log'
set +e; out=$(run_hook "$ignored_log"); status=$?; set -e
[[ $status -eq 0 ]] \
  && ok "logs in ignored directories (.system_generated, .venv) pass exit 0" \
  || bad "logs in ignored directories (.system_generated, .venv) pass exit 0" "exit $status, out: $out"

# --- 10. Live workspace check under git repo fixture --------------------------
git_fixture="$TMP/git_fixture"
mkdir -p "$git_fixture"
git -C "$git_fixture" init -q
echo "hello" > "$git_fixture/app.py"
git -C "$git_fixture" add app.py
git -C "$git_fixture" -c user.name="Test" -c user.email="test@example.com" commit -qm "initial"

# Clean git fixture passes
set +e; out=$(CLEAN_STATE_GUARD_REPO_DIR="$git_fixture" bash "$HOOK" 2>&1); status=$?; set -e
[[ $status -eq 0 ]] \
  && ok "clean git fixture passes exit 0" \
  || bad "clean git fixture passes exit 0" "exit $status, out: $out"

# Untracked scratch in git fixture blocks
echo "scratch" > "$git_fixture/scratch.py"
set +e; out=$(CLEAN_STATE_GUARD_REPO_DIR="$git_fixture" bash "$HOOK" 2>&1); status=$?; set -e
[[ $status -eq 2 && "$out" =~ "scratch.py" ]] \
  && ok "untracked scratch file in git fixture blocks exit 2" \
  || bad "untracked scratch file in git fixture blocks exit 2" "exit $status, out: $out"

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
