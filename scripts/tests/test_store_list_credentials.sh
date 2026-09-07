#!/usr/bin/env bash
# test_store_list_credentials.sh — list_credentials must not hide entries
# whose keychain account field is NULL (the apidog entry was shaped that way,
# so `setup-credentials.sh apidog list` reported it as absent).
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
PASS=0; FAIL=0

# Prefix follows THIS repo's identity, never a fixed name.
ID=$(head -1 "$REPO_DIR/.skills-repo-id" | tr -d '[:space:]')

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  PASS: $name"; PASS=$((PASS+1))
  else
    echo "  FAIL: $name (expected to contain '$expected', got: $actual)"; FAIL=$((FAIL+1))
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

# A stub keychain: one normal entry, one with a NULL account field. Real
# `security` is never called, so the developer's keychain is untouched.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/security" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "dump-keychain" ]] || exit 0
cat <<'DUMP'
keychain: "/Library/Keychains/login.keychain-db"
    "acct"<blob>="hero@example.com"
    "svce"<blob>="__ID__:jira-https---example-atlassian-net"
keychain: "/Library/Keychains/login.keychain-db"
    "acct"<blob>=<NULL>
    "svce"<blob>="__ID__:apidog"
keychain: "/Library/Keychains/login.keychain-db"
    "acct"<blob>="unrelated"
    "svce"<blob>="some-other-app:token"
DUMP
STUB
sed -i.bak "s/__ID__/$ID/g" "$TMP/bin/security" && rm -f "$TMP/bin/security.bak"
chmod +x "$TMP/bin/security"

# _store.sh derives its prefix from a .skills-repo-id beside itself.
mkdir -p "$TMP/repo/scripts/credentials"
cp "$REPO_DIR/scripts/credentials/_store.sh" "$TMP/repo/scripts/credentials/"
echo "$ID" > "$TMP/repo/.skills-repo-id"

OUT=$(PATH="$TMP/bin:/usr/bin:/bin" bash -c "
  source '$TMP/repo/scripts/credentials/_store.sh'
  list_credentials
" 2>&1)

check "NULL-account entry is listed"        "$ID:apidog"  "$OUT"
check "NULL account renders a placeholder"  "<no account>"               "$OUT"
check "normal entry still listed"           "hero@example.com"           "$OUT"
check "other apps' entries excluded"        ""                           "$OUT"
if [[ "$OUT" == *"some-other-app"* ]]; then
  echo "  FAIL: unrelated prefix leaked into the listing"; FAIL=$((FAIL+1))
else
  echo "  PASS: unrelated prefix excluded"; PASS=$((PASS+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
