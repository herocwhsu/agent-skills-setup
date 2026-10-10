#!/usr/bin/env bash
# Tests for scripts/session-clean.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_DIR/scripts/session-clean.sh"
[[ -f "$SCRIPT" ]] || { echo "FAIL: script not found at $SCRIPT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# Helper to build a clean fixture with valid state layer and clean workspace
fixture_repo() {
  local d="$TMP/$1"
  mkdir -p "$d/.claude/hooks" "$d/scripts"
  echo '{"features": []}' > "$d/feature_list.json"
  echo '# progress' > "$d/PROGRESS.md"
  echo '#!/usr/bin/env bash' > "$d/init.sh"

  # Copy guards
  cp "$REPO_DIR/.claude/hooks/clean-state-guard.sh" "$d/.claude/hooks/"
  cp "$REPO_DIR/.claude/hooks/state-layer-guard.sh" "$d/.claude/hooks/"
  chmod +x "$d/.claude/hooks/"*.sh
  git -C "$d" init -q
  git -C "$d" add .
  git -C "$d" -c user.name="Test" -c user.email="test@example.com" commit -qm "init"
  echo "$d"
}

# --- 1. Clean fixture passes with clean handoff banner ------------------------
d=$(fixture_repo "clean")
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "ALL INVARIANTS SATISFIED" ]] \
  && ok "clean fixture passes with clean handoff banner" \
  || bad "clean fixture passes with clean handoff banner" "exit $status, out: $out"

# --- 2. --check mode passes without purging ----------------------------------
d=$(fixture_repo "check_mode")
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" --check 2>&1); status=$?; set -e
[[ $status -eq 0 && "$out" =~ "Read-only check mode" ]] \
  && ok "--check mode passes without purging" \
  || bad "--check mode passes without purging" "exit $status, out: $out"

# --- 3. Purges __pycache__ and cache dirs ------------------------------------
d=$(fixture_repo "cache_test")
mkdir -p "$d/src/__pycache__" "$d/.pytest_cache"
echo "cache" > "$d/src/__pycache__/app.cpython-314.pyc"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 0 && ! -d "$d/src/__pycache__" && ! -d "$d/.pytest_cache" ]] \
  && ok "purges __pycache__ and .pytest_cache" \
  || bad "purges __pycache__ and .pytest_cache" "exit $status, caches still present"

# --- 4. Dirty workspace with scratch file exits 2 -----------------------------
d=$(fixture_repo "dirty_test")
echo "scratch code" > "$d/scratch.py"
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" 2>&1); status=$?; set -e
[[ $status -eq 2 && "$out" =~ "Invariant 4 Violated" ]] \
  && ok "dirty workspace with scratch file exits 2" \
  || bad "dirty workspace with scratch file exits 2" "exit $status, out: $out"

# --- 5. Idempotent: running repeatedly produces exit 0 ------------------------
d=$(fixture_repo "idempotent_test")
status1=0; status2=0
SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" >/dev/null 2>&1 || status1=$?
SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" >/dev/null 2>&1 || status2=$?
[[ $status1 -eq 0 && $status2 -eq 0 ]] \
  && ok "idempotent repeated execution passes exit 0" \
  || bad "idempotent repeated execution passes exit 0" "run1: $status1, run2: $status2"

# --- 6. Unknown argument exits 2 ---------------------------------------------
d=$(fixture_repo "bad_arg")
set +e; out=$(SESSION_CLEAN_REPO_DIR="$d" bash "$SCRIPT" --bogus 2>&1); status=$?; set -e
[[ $status -eq 2 && "$out" =~ "Unknown option" ]] \
  && ok "unknown option exits 2" \
  || bad "unknown option exits 2" "exit $status, out: $out"

echo ""
echo "test_session_clean: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
