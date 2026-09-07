#!/usr/bin/env bash
# test_store_list_credentials.sh — list_credentials and delete_credential must
# work on every backend _store.sh claims to support.
#
# Two bugs this covers:
#   1. list_credentials hid entries whose keychain account field was NULL, so
#      `setup-credentials.sh apidog list` reported a stored token as absent.
#   2. neither list_credentials nor delete_credential had a linux-file branch,
#      so on the JSON fallback the listing printed only its header and a
#      delete silently did nothing.
#
# Each case stubs `uname` so _os() is forced rather than inherited from the
# host. Without that, the darwin path is the only one a macOS developer ever
# exercises and the Linux branches ship untested -- which is how (2) reached
# CI red on a clean ubuntu runner.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
PASS=0; FAIL=0

# Deliberately NOT the real marker: _store.sh falls back to a hardcoded default
# equal to this repo's own id, so a test using the real id would pass even if
# marker derivation were broken entirely.
ID="probe-repo"

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  PASS: $name"; PASS=$((PASS+1))
  else
    echo "  FAIL: $name (expected to contain '$expected', got: $actual)"; FAIL=$((FAIL+1))
  fi
}

refute() {
  local name="$1" unexpected="$2" actual="$3"
  if [[ "$actual" != *"$unexpected"* ]]; then
    echo "  PASS: $name"; PASS=$((PASS+1))
  else
    echo "  FAIL: $name (should not contain '$unexpected', got: $actual)"; FAIL=$((FAIL+1))
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A throwaway copy of _store.sh, with a marker beside it so the prefix derives.
mkdir -p "$TMP/repo/scripts/credentials"
cp "$REPO_DIR/scripts/credentials/_store.sh" "$TMP/repo/scripts/credentials/"
echo "$ID" > "$TMP/repo/.skills-repo-id"

# ---------------------------------------------------------------------------
# Backend 1: darwin (stubbed `security dump-keychain`)
# ---------------------------------------------------------------------------
D="$TMP/darwin"; mkdir -p "$D/bin" "$D/home"
printf '#!/usr/bin/env bash\necho Darwin\n' > "$D/bin/uname"
cat > "$D/bin/security" <<STUB
#!/usr/bin/env bash
[[ "\$1" == "dump-keychain" ]] || exit 0
cat <<DUMP
keychain: "/Library/Keychains/login.keychain-db"
    "acct"<blob>="hero@example.com"
    "svce"<blob>="$ID:jira-https---example-atlassian-net"
keychain: "/Library/Keychains/login.keychain-db"
    "acct"<blob>=<NULL>
    "svce"<blob>="$ID:apidog"
keychain: "/Library/Keychains/login.keychain-db"
    "acct"<blob>="unrelated"
    "svce"<blob>="some-other-app:token"
DUMP
STUB
chmod +x "$D/bin/uname" "$D/bin/security"

OUT=$(PATH="$D/bin:/usr/bin:/bin" HOME="$D/home" bash -c "
  source '$TMP/repo/scripts/credentials/_store.sh'
  [[ \$(_os) == darwin ]] || { echo \"BACKEND MISMATCH: \$(_os)\"; exit 1; }
  list_credentials
" 2>&1)

echo "darwin backend:"
check  "listing produced its header"        "Stored credentials (prefix: $ID:)" "$OUT"
check  "NULL-account entry is listed"       "$ID:apidog"       "$OUT"
check  "NULL account renders a placeholder" "<no account>"     "$OUT"
check  "normal entry keeps its account"     "hero@example.com" "$OUT"
refute "other apps' entries excluded"       "some-other-app"   "$OUT"

# ---------------------------------------------------------------------------
# Backend 2: linux-file (JSON fallback store)
# ---------------------------------------------------------------------------
# _os() returns linux-file only when secret-tool is absent, so PATH holds just
# the stubs plus the binaries _store.sh actually calls -- never a system dir
# that might carry secret-tool.
L="$TMP/linux"; mkdir -p "$L/bin" "$L/home"
printf '#!/usr/bin/env bash\necho Linux\n' > "$L/bin/uname"
chmod +x "$L/bin/uname"
for b in bash python3 head tr mkdir dirname chmod cat rm; do
  src=$(PATH=/usr/bin:/bin command -v "$b" 2>/dev/null) && ln -sf "$src" "$L/bin/$b"
done

RT="$L/home/.$ID"; mkdir -p "$RT"
cat > "$RT/credentials.json" <<JSON
{
  "$ID:jira-https---example-atlassian-net:hero@example.com": "token-1",
  "$ID:apidog:": "token-2",
  "some-other-app:token:someone": "token-3"
}
JSON

run_linux() {
  PATH="$L/bin" HOME="$L/home" bash -c "
    source '$TMP/repo/scripts/credentials/_store.sh'
    [[ \$(_os) == linux-file ]] || { echo \"BACKEND MISMATCH: \$(_os)\"; exit 1; }
    $1
  " 2>&1
}

OUT=$(run_linux "list_credentials")
echo "linux-file backend:"
# Guard against vacuous refutes: if the backend never ran, every refute below
# would pass on an error message. Assert the listing actually happened.
check  "listing produced its header"        "Stored credentials (prefix: $ID:)" "$OUT"
check  "JSON store is listed at all"        "$ID:apidog"       "$OUT"
check  "empty account renders placeholder"  "<no account>"     "$OUT"
check  "normal entry keeps its account"     "hero@example.com" "$OUT"
refute "other apps' entries excluded"       "some-other-app"   "$OUT"
refute "no secret value is ever printed"    "token-1"          "$OUT"

OUT=$(run_linux "delete_credential apidog ''; list_credentials")
check  "delete removes the entry"           "deleted"          "$OUT"
refute "deleted entry no longer listed"     "$ID:apidog"       "$OUT"
check  "unrelated entry survives delete"    "hero@example.com" "$OUT"

OUT=$(run_linux "delete_credential nonexistent someone")
check  "deleting a missing entry is graceful" "(not found)"    "$OUT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
