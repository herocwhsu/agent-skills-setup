#!/usr/bin/env bash
# Tests for .claude/hooks/credential-backend-guard.sh and
# scripts/credential-backend-check.py.
#
# Uses CREDENTIAL_BACKEND_GUARD_REPO_DIR to point at throwaway trees. Asserting
# against the real _store.sh alone would stop being a test the moment that file
# is complete -- which it now is, so every case here builds its own fixture.
#
# Exit 2 is asserted explicitly: it is the only code Claude Code feeds back to
# the agent, and a gate returning 1 presents as a gate while blocking nothing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOK="$REPO_DIR/.claude/hooks/credential-backend-guard.sh"
CHECKER="$REPO_DIR/scripts/credential-backend-check.py"
[[ -f "$HOOK" ]]    || { echo "FAIL: hook not found at $HOOK"; exit 1; }
[[ -f "$CHECKER" ]] || { echo "FAIL: checker not found at $CHECKER"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# fixture <name> <store-body> -> echoes a repo-shaped dir carrying that _store.sh
fixture() {
  # Separate statements: `local a=$1 b=$TMP/$a` expands every argument before the
  # builtin assigns any, so $a is still unset there and set -u aborts.
  local name="$1"
  local body="$2"
  local d="$TMP/$name"
  mkdir -p "$d/scripts/credentials"
  cp "$CHECKER" "$d/scripts/credential-backend-check.py"
  printf '%s\n' "$body" > "$d/scripts/credentials/_store.sh"
  echo "$d"
}

run_hook() { CREDENTIAL_BACKEND_GUARD_REPO_DIR="$1" bash "$HOOK" 2>&1; }

# Every fixture shares this _os(): three real backends plus the unknown
# sentinel, matching the shipped one.
OS_FUNC='_os() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux)
      if command -v secret-tool &>/dev/null; then
        echo "linux-gui"
      else
        echo "linux-file"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}'

# --- 1. the shipped bug shape blocks with exit 2 ---------------------------
# list_credentials had exactly this: darwin and linux-gui handled, linux-file
# absent, so the JSON store printed a header and no rows.
d=$(fixture missing "$OS_FUNC
list_credentials() {
  case \"\$(_os)\" in
    darwin) echo a ;;
    linux-gui) echo b ;;
    linux-headless) echo c ;;
  esac
}")
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 2 ]] && ok "missing backend blocks with exit 2" \
                    || bad "missing backend blocks with exit 2" "exit $status"
[[ "$out" == *"linux-file"* ]] && ok "message names the missing backend" \
                               || bad "message names the missing backend" "$out"
[[ "$out" == *"list_credentials"* ]] && ok "message names the function" \
                                    || bad "message names the function" "$out"

# --- 2. a complete dispatch passes ----------------------------------------
d=$(fixture complete "$OS_FUNC
list_credentials() {
  case \"\$(_os)\" in
    darwin) echo a ;;
    linux-gui) echo b ;;
    linux-file) echo c ;;
  esac
}")
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 0 ]] && ok "complete dispatch passes" \
                    || bad "complete dispatch passes" "exit $status: $out"

# --- 3. a catch-all cannot fall through, so it is complete ----------------
d=$(fixture catchall "$OS_FUNC
read_credential() {
  case \"\$(_os)\" in
    darwin) echo a ;;
    *) echo fallback ;;
  esac
}")
set +e; status=0; out=$(run_hook "$d") || status=$?; set -e
[[ $status -eq 0 ]] && ok "catch-all counts as complete" \
                    || bad "catch-all counts as complete" "exit $status: $out"

# --- 4. one incomplete dispatch among several is still caught -------------
d=$(fixture mixed "$OS_FUNC
store_credential() {
  case \"\$(_os)\" in
    darwin) echo a ;;
    linux-gui) echo b ;;
    linux-file) echo c ;;
  esac
}
delete_credential() {
  case \"\$(_os)\" in
    darwin) echo a ;;
    linux-gui) echo b ;;
  esac
}")
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 2 ]] && ok "one bad dispatch among good ones blocks" \
                    || bad "one bad dispatch among good ones blocks" "exit $status"
[[ "$out" == *"delete_credential"* && "$out" != *"store_credential"* ]] \
  && ok "only the incomplete function is reported" \
  || bad "only the incomplete function is reported" "$out"

# --- 5. a new backend in _os() must propagate to every dispatch -----------
# The point of a source-level guard: adding a backend cannot silently leave a
# dispatch behind, even though every previously-known backend is handled.
d=$(fixture newbackend '_os() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux) echo "linux-file" ;;
    FreeBSD) echo "bsd-keyring" ;;
    *) echo "unknown" ;;
  esac
}
list_credentials() {
  case "$(_os)" in
    darwin) echo a ;;
    linux-file) echo b ;;
  esac
}')
set +e; out=$(run_hook "$d"); status=$?; set -e
[[ $status -eq 2 ]] && ok "a newly added backend is required everywhere" \
                    || bad "a newly added backend is required everywhere" "exit $status"
[[ "$out" == *"bsd-keyring"* ]] && ok "message names the new backend" \
                               || bad "message names the new backend" "$out"

# --- 6. the unknown sentinel is not a storage backend --------------------
# _os() echoes "unknown" for an unsupported platform; there is no keychain to
# dispatch to, so its absence is not the defect this guard is about.
d=$(fixture sentinel "$OS_FUNC
list_credentials() {
  case \"\$(_os)\" in
    darwin) echo a ;;
    linux-gui) echo b ;;
    linux-file) echo c ;;
  esac
}")
set +e; status=0; out=$(run_hook "$d") || status=$?; set -e
[[ $status -eq 0 ]] && ok "the unknown sentinel is not required" \
                    || bad "the unknown sentinel is not required" "exit $status: $out"

# --- 7. a guard that cannot run is not a guard that failed ---------------
d="$TMP/empty"; mkdir -p "$d/scripts"
set +e; status=0; out=$(run_hook "$d") || status=$?; set -e
[[ $status -eq 0 ]] && ok "absent _store.sh skips rather than crashes" \
                    || bad "absent _store.sh skips rather than crashes" "exit $status: $out"

# --- 8. the real tree passes ---------------------------------------------
set +e; status=0; out=$(bash "$HOOK") || status=$?; set -e
[[ $status -eq 0 ]] && ok "the shipped _store.sh passes" \
                    || bad "the shipped _store.sh passes" "exit $status: $out"

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
