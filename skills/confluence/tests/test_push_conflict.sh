#!/usr/bin/env bash
# test_push_conflict.sh — exercise push.py against a mock REST server.
#
# Covers:
#   1. happy path: GET version matches stored, PUT succeeds, meta.json
#      version bumped
#   2. conflict abort: GET version > stored, exit 5, meta.json
#      unchanged
#   3. auth detection: PAT-format secret produces Bearer header
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUSH="$SKILL_DIR/lib/push.py"

TMP=$(mktemp -d)
trap '[[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

# --- Mock server ---
cat > "$TMP/server.py" <<'PYEOF'
import http.server, json, os, sys, threading

# Behavior knob written to a file so the test can switch modes between
# requests without restarting the server.
def mode():
    try:
        with open(os.environ["MODE_FILE"]) as f:
            return f.read().strip()
    except FileNotFoundError:
        return "match"

# Records the last Authorization header so the test can assert auth shape.
def record(header_value):
    with open(os.environ["AUTH_RECORD"], "w") as f:
        f.write(header_value or "")

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass

    def do_GET(self):
        record(self.headers.get("Authorization", ""))
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        version = 13 if mode() == "conflict" else 12
        body = json.dumps({"id": "999", "version": {"number": version}})
        self.wfile.write(body.encode())

    def do_PUT(self):
        record(self.headers.get("Authorization", ""))
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        payload = json.loads(body)
        # echo back with the version we received
        new_version = payload["version"]["number"]
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "id": "999", "version": {"number": new_version}, "title": payload["title"]
        }).encode())

port = int(os.environ["PORT"])
server = http.server.HTTPServer(("127.0.0.1", port), H)
threading.Thread(target=server.serve_forever, daemon=True).start()
sys.stdout.write("ready\n"); sys.stdout.flush()
import signal; signal.pause()
PYEOF

PORT=$((40000 + RANDOM % 1000))
MODE_FILE="$TMP/mode"
AUTH_RECORD="$TMP/auth"
echo match > "$MODE_FILE"

PORT=$PORT MODE_FILE=$MODE_FILE AUTH_RECORD=$AUTH_RECORD \
  python3 "$TMP/server.py" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!

# Wait for "ready"
for _ in $(seq 1 30); do
  grep -q ready "$TMP/server.log" 2>/dev/null && break
  sleep 0.1
done
grep -q ready "$TMP/server.log" || { cat "$TMP/server.log"; echo "FAIL: server did not start"; exit 1; }

cat > "$TMP/page.meta.json" <<EOF
{"pageId":"999","version":12,"space":"PP2","ancestor":"100","title":"Test","host":"http://127.0.0.1:$PORT","anchors":{}}
EOF
echo "<p>hello</p>" > "$TMP/page.xhtml"

# --- Test 1: happy path with Basic Auth ---
echo match > "$MODE_FILE"
CONFLUENCE_PASS=plainpassword python3 "$PUSH" \
  --host "http://127.0.0.1:$PORT" --user testuser \
  --meta-file "$TMP/page.meta.json" --xhtml "$TMP/page.xhtml" >"$TMP/out1.txt" 2>&1 \
  || { cat "$TMP/out1.txt"; echo "FAIL test 1: push exited non-zero"; exit 1; }

grep -q "v13" "$TMP/out1.txt" || { cat "$TMP/out1.txt"; echo "FAIL test 1: expected v13 in output"; exit 1; }
python3 -c "import json; assert json.load(open('$TMP/page.meta.json'))['version']==13" \
  || { echo "FAIL test 1: meta.json version not bumped"; exit 1; }
grep -q "^Basic " "$AUTH_RECORD" \
  || { echo "FAIL test 1: expected Basic auth, got: $(cat $AUTH_RECORD)"; exit 1; }
echo "OK test 1: happy path with Basic Auth, meta bumped to v13"

# --- Test 2: conflict abort ---
# reset stored version to 12, server now reports 14
python3 -c "
import json
m = json.load(open('$TMP/page.meta.json')); m['version']=12
json.dump(m, open('$TMP/page.meta.json','w'))
"
echo conflict > "$MODE_FILE"

set +e
CONFLUENCE_PASS=plainpassword python3 "$PUSH" \
  --host "http://127.0.0.1:$PORT" --user testuser \
  --meta-file "$TMP/page.meta.json" --xhtml "$TMP/page.xhtml" >"$TMP/out2.txt" 2>&1
rc=$?
set -e

[[ $rc -eq 5 ]] || { cat "$TMP/out2.txt"; echo "FAIL test 2: expected exit 5, got $rc"; exit 1; }
grep -q "moved from v12 to v13" "$TMP/out2.txt" \
  || { cat "$TMP/out2.txt"; echo "FAIL test 2: expected conflict message"; exit 1; }
python3 -c "import json; assert json.load(open('$TMP/page.meta.json'))['version']==12" \
  || { echo "FAIL test 2: meta.json was modified on conflict"; exit 1; }
echo "OK test 2: conflict aborted, meta unchanged"

# --- Test 3: PAT-format secret produces Bearer header ---
python3 -c "
import json
m = json.load(open('$TMP/page.meta.json')); m['version']=12  # match server's match-mode value
json.dump(m, open('$TMP/page.meta.json','w'))
"
echo match > "$MODE_FILE"

# 32-char PAT-shaped token, no colon
CONFLUENCE_PASS="abcDEF0123456789-_=abcDEF0123456789" python3 "$PUSH" \
  --host "http://127.0.0.1:$PORT" --user testuser \
  --meta-file "$TMP/page.meta.json" --xhtml "$TMP/page.xhtml" >"$TMP/out3.txt" 2>&1 \
  || { cat "$TMP/out3.txt"; echo "FAIL test 3"; exit 1; }

grep -q "^Bearer " "$AUTH_RECORD" \
  || { echo "FAIL test 3: expected Bearer auth, got: $(cat $AUTH_RECORD)"; exit 1; }
echo "OK test 3: PAT auto-detected, sent as Bearer"

echo ""
echo "All push/conflict tests passed."
