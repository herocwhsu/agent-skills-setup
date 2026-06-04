#!/usr/bin/env bash
# test_push.sh — exercise push.py (create-only) against a mock REST server.
#
# Covers:
#   1. happy create: POST returns id 999, version 1; stdout is JSON line
#      with the new page id; stderr mentions creation
#   2. 401 on POST returns exit code 3
#   3. PAT-format secret produces Bearer auth header
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
        return "ok"

# Records the last Authorization header so the test can assert auth shape.
def record(header_value):
    with open(os.environ["AUTH_RECORD"], "w") as f:
        f.write(header_value or "")

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass

    def do_POST(self):
        record(self.headers.get("Authorization", ""))
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        if mode() == "auth_fail":
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"message":"Unauthorized"}')
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        body = json.dumps({
            "id": "999",
            "version": {"number": 1},
            "title": "Test",
            "_links": {"webui": "/display/PP2/Test", "tinyui": "/x/abc"},
        })
        self.wfile.write(body.encode())

port = int(os.environ["PORT"])
server = http.server.HTTPServer(("127.0.0.1", port), H)
threading.Thread(target=server.serve_forever, daemon=True).start()
sys.stdout.write("ready\n"); sys.stdout.flush()
import signal; signal.pause()
PYEOF

PORT=$((40000 + RANDOM % 1000))
MODE_FILE="$TMP/mode"
AUTH_RECORD="$TMP/auth"
echo ok > "$MODE_FILE"

PORT=$PORT MODE_FILE=$MODE_FILE AUTH_RECORD=$AUTH_RECORD \
  python3 "$TMP/server.py" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!

# Wait for "ready"
for _ in $(seq 1 30); do
  grep -q ready "$TMP/server.log" 2>/dev/null && break
  sleep 0.1
done
grep -q ready "$TMP/server.log" || { cat "$TMP/server.log"; echo "FAIL: server did not start"; exit 1; }

echo "<p>hello</p>" > "$TMP/page.xhtml"

# --- Test 1: happy create with Basic Auth ---
echo ok > "$MODE_FILE"
CONFLUENCE_PASS=plainpassword python3 "$PUSH" \
  --host "http://127.0.0.1:$PORT" --user testuser \
  --xhtml "$TMP/page.xhtml" \
  --space PP2 --parent 100 --title "Test" >"$TMP/out1.txt" 2>"$TMP/err1.txt" \
  || { cat "$TMP/out1.txt" "$TMP/err1.txt"; echo "FAIL test 1: push exited non-zero"; exit 1; }

# stdout should be a JSON line with id "999" and version 1
python3 -c "
import json
line = open('$TMP/out1.txt').read().strip()
data = json.loads(line)
assert data['id'] == '999', f'expected id 999, got {data}'
assert data['version'] == 1, f'expected version 1, got {data}'
" || { cat "$TMP/out1.txt"; echo "FAIL test 1: stdout JSON shape"; exit 1; }

grep -q "Created page #999" "$TMP/err1.txt" \
  || { cat "$TMP/err1.txt"; echo "FAIL test 1: expected Created msg on stderr"; exit 1; }

grep -q "^Basic " "$AUTH_RECORD" \
  || { echo "FAIL test 1: expected Basic auth, got: $(cat "$AUTH_RECORD")"; exit 1; }
echo "OK test 1: happy create with Basic Auth, id 999 returned via JSON stdout"

# --- Test 2: 401 returns exit 3 ---
echo auth_fail > "$MODE_FILE"
set +e
CONFLUENCE_PASS=plainpassword python3 "$PUSH" \
  --host "http://127.0.0.1:$PORT" --user testuser \
  --xhtml "$TMP/page.xhtml" \
  --space PP2 --title "Test" >"$TMP/out2.txt" 2>"$TMP/err2.txt"
rc=$?
set -e

[[ $rc -eq 3 ]] || { cat "$TMP/err2.txt"; echo "FAIL test 2: expected exit 3, got $rc"; exit 1; }
grep -q "auth failed" "$TMP/err2.txt" \
  || { cat "$TMP/err2.txt"; echo "FAIL test 2: expected auth-failed message"; exit 1; }
echo "OK test 2: 401 mapped to exit 3"

# --- Test 3: PAT-format secret produces Bearer header ---
echo ok > "$MODE_FILE"
# 35-char PAT-shaped token, no colon
CONFLUENCE_PASS="abcDEF0123456789-_=abcDEF0123456789" python3 "$PUSH" \
  --host "http://127.0.0.1:$PORT" --user testuser \
  --xhtml "$TMP/page.xhtml" \
  --space PP2 --title "Test" >"$TMP/out3.txt" 2>"$TMP/err3.txt" \
  || { cat "$TMP/out3.txt" "$TMP/err3.txt"; echo "FAIL test 3"; exit 1; }

grep -q "^Bearer " "$AUTH_RECORD" \
  || { echo "FAIL test 3: expected Bearer auth, got: $(cat "$AUTH_RECORD")"; exit 1; }
echo "OK test 3: PAT auto-detected, sent as Bearer"

# --- Test 4: missing --xhtml file returns exit 2 ---
set +e
CONFLUENCE_PASS=plain python3 "$PUSH" \
  --host "http://127.0.0.1:$PORT" --user testuser \
  --xhtml "$TMP/does-not-exist.xml" \
  --space PP2 --title "x" >"$TMP/out4.txt" 2>"$TMP/err4.txt"
rc=$?
set -e
[[ $rc -eq 2 ]] || { cat "$TMP/err4.txt"; echo "FAIL test 4: expected exit 2, got $rc"; exit 1; }
grep -q "cannot read" "$TMP/err4.txt" \
  || { cat "$TMP/err4.txt"; echo "FAIL test 4: expected 'cannot read' message"; exit 1; }
echo "OK test 4: missing --xhtml file -> exit 2"

# --- Test 5: malformed POST response (server returns 200 with no id) returns exit 6 ---
# Need a separate mock server that returns malformed bodies.
cat > "$TMP/server2.py" <<'PYEOF'
import http.server, os, sys, threading
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"unexpected":"shape"}')
port = int(os.environ["PORT"])
srv = http.server.HTTPServer(("127.0.0.1", port), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
sys.stdout.write("ready\n"); sys.stdout.flush()
import signal; signal.pause()
PYEOF

PORT2=$((46000 + RANDOM % 1000))
PORT=$PORT2 python3 "$TMP/server2.py" >"$TMP/server2.log" 2>&1 &
SERVER2_PID=$!
trap '[[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null; [[ -n "${SERVER2_PID:-}" ]] && kill "$SERVER2_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
for _ in $(seq 1 30); do grep -q ready "$TMP/server2.log" 2>/dev/null && break; sleep 0.1; done
grep -q ready "$TMP/server2.log" || { cat "$TMP/server2.log"; echo "FAIL test 5: server didn't start"; exit 1; }

echo "<p>x</p>" > "$TMP/page.xhtml"
set +e
CONFLUENCE_PASS=plain python3 "$PUSH" \
  --host "http://127.0.0.1:$PORT2" --user testuser \
  --xhtml "$TMP/page.xhtml" \
  --space PP2 --title "x" >"$TMP/out5.txt" 2>"$TMP/err5.txt"
rc=$?
set -e
[[ $rc -eq 6 ]] || { cat "$TMP/err5.txt"; echo "FAIL test 5: expected exit 6, got $rc"; exit 1; }
grep -q "missing id/version" "$TMP/err5.txt" \
  || { cat "$TMP/err5.txt"; echo "FAIL test 5: expected 'missing id/version' message"; exit 1; }
echo "OK test 5: malformed POST response -> exit 6"

echo ""
echo "All push tests passed."
