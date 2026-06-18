#!/usr/bin/env bash
# Tests for scripts/apidog-share-fetch.py — Remix turbo-stream parser.
# Uses --from-file flag to bypass HTTP and feed the fixture directly.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_DIR/scripts/apidog-share-fetch.py"
FIXTURE="$REPO_DIR/scripts/tests/fixtures/apidog-share-37491818.data"

[[ -f "$SCRIPT" ]]  || { echo "FAIL: script not found at $SCRIPT"; exit 1; }
[[ -f "$FIXTURE" ]] || { echo "FAIL: fixture not found at $FIXTURE"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: parser produces valid JSON ---
out="$TMP/out.json"
if ! python3 "$SCRIPT" --share-uuid 00000000-0000-0000-0000-000000000000 --endpoint-id 1 --from-file "$FIXTURE" > "$out" 2>"$TMP/err"; then
    echo "FAIL: script exited non-zero"
    cat "$TMP/err"
    exit 1
fi
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$out" \
    || { echo "FAIL: output is not valid JSON"; exit 1; }
echo "OK: output is valid JSON"

# --- Test 2: extracted top-level fields match the fixture ---
python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["id"] == 37491818, f"id={d['id']!r}"
assert d["method"] == "POST", f"method={d['method']!r}"
assert d["path"] == "/auth/password-forgot", f"path={d['path']!r}"
assert d["name"] == "Initiate forgot-password flow", f"name={d['name']!r}"
assert d["request"]["media_type"] == "application/json"
PY
echo "OK: top-level fields match"

# --- Test 3: response codes and type enums extracted correctly ---
python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
codes = sorted(r["code"] for r in d["responses"])
assert "200" in codes and "400" in codes and "401" in codes, f"codes={codes}"
# 400 response carries the type-enum override [invalid-request, code-expired]
r400 = next(r for r in d["responses"] if r["code"] == "400")
flat = [t for enum in r400["type_enums"] for t in enum]
assert "/problems/invalid-request" in flat, f"400 enums={r400['type_enums']}"
assert "/problems/code-expired" in flat,  f"400 enums={r400['type_enums']}"
# 401 carries [invalid-credentials]
r401 = next(r for r in d["responses"] if r["code"] == "401")
flat401 = [t for enum in r401["type_enums"] for t in enum]
assert "/problems/invalid-credentials" in flat401, f"401 enums={r401['type_enums']}"
PY
echo "OK: response codes and type enums extracted"

# --- Test 4: output is stable across invocations (sort_keys=True + same fixture) ---
out2="$TMP/out2.json"
python3 "$SCRIPT" --share-uuid 00000000-0000-0000-0000-000000000000 --endpoint-id 1 --from-file "$FIXTURE" > "$out2"
diff -q "$out" "$out2" >/dev/null || { echo "FAIL: output is not deterministic"; exit 1; }
echo "OK: output is deterministic"

# --- Test 5: --share-uuid is required ---
if python3 "$SCRIPT" --endpoint-id 1 --from-file "$FIXTURE" >/dev/null 2>&1; then
    echo "FAIL: missing --share-uuid should fail"
    exit 1
fi
echo "OK: --share-uuid is required"

# --- Test 6: mutually exclusive --endpoint-id / --path-prefix / --list ---
if python3 "$SCRIPT" --share-uuid x --endpoint-id 1 --list >/dev/null 2>&1; then
    echo "FAIL: --endpoint-id and --list together should fail"
    exit 1
fi
echo "OK: --endpoint-id / --path-prefix / --list are mutually exclusive"

echo "ALL TESTS PASSED"
