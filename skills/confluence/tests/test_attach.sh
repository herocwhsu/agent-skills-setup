#!/usr/bin/env bash
# test_attach.sh — exercise attach.py against a mock attachment endpoint.
#
# Covers:
#   1. happy path: a list of local files via --files uploads them all
#   2. missing file: default behavior is exit 6; --continue-on-error
#      warns and continues
#   3. multipart correctness: X-Atlassian-Token: nocheck, multipart
#      boundary, filename in form-data
#   4. page-id flag in URL: upload URL contains
#      /content/<page-id>/child/attachment
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ATTACH="$SKILL_DIR/lib/attach.py"

TMP=$(mktemp -d)
trap '[[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

# Mock server records request body + path to a file and replies 200.
cat > "$TMP/server.py" <<'PYEOF'
import http.server, os, sys, threading

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        with open(os.environ["BODY_DUMP"], "ab") as f:
            f.write(b"=== request ===\n")
            f.write(f"PATH: {self.path}\n".encode())
            f.write(f"X-Atlassian-Token: {self.headers.get('X-Atlassian-Token', '')}\n".encode())
            f.write(f"Content-Type: {self.headers.get('Content-Type', '')}\n".encode())
            f.write(b"---body---\n")
            f.write(self.rfile.read(length))
            f.write(b"\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"results":[{"id":"att1","title":"img"}]}')

port = int(os.environ["PORT"])
srv = http.server.HTTPServer(("127.0.0.1", port), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
sys.stdout.write("ready\n"); sys.stdout.flush()
import signal; signal.pause()
PYEOF

PORT=$((41000 + RANDOM % 1000))
BODY_DUMP="$TMP/bodies"
: > "$BODY_DUMP"

PORT=$PORT BODY_DUMP=$BODY_DUMP \
  python3 "$TMP/server.py" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 30); do
  grep -q ready "$TMP/server.log" 2>/dev/null && break
  sleep 0.1
done
grep -q ready "$TMP/server.log" || { cat "$TMP/server.log"; echo "FAIL: server didn't start"; exit 1; }

mkdir "$TMP/page"
echo "fake png 1" > "$TMP/page/diagram.png"
echo "fake png 2" > "$TMP/page/chart.png"

# --- Test 1: upload happy path with two local files ---
CONFLUENCE_PASS=plainpassword python3 "$ATTACH" \
  --host "http://127.0.0.1:$PORT" \
  --user testuser \
  --page-id 999 \
  --files "$TMP/page/diagram.png" "$TMP/page/chart.png" >"$TMP/out1.txt" 2>"$TMP/err1.txt" \
  || { cat "$TMP/out1.txt" "$TMP/err1.txt"; echo "FAIL test 1: attach exited non-zero"; exit 1; }

grep -q "Uploaded 2 attachment" "$TMP/err1.txt" \
  || { cat "$TMP/err1.txt"; echo "FAIL test 1: expected 2 uploads"; exit 1; }
# server should have logged exactly two requests
req_count=$(grep -c "=== request ===" "$BODY_DUMP")
[[ $req_count -eq 2 ]] || { echo "FAIL test 1: expected 2 server requests, got $req_count"; exit 1; }
echo "OK test 1: two local files uploaded"

# --- Test 2a: missing file default behavior (exit 6) ---
: > "$BODY_DUMP"
set +e
CONFLUENCE_PASS=plainpassword python3 "$ATTACH" \
  --host "http://127.0.0.1:$PORT" \
  --user testuser \
  --page-id 999 \
  --files "$TMP/page/not-here.png" >"$TMP/out2a.txt" 2>"$TMP/err2a.txt"
rc=$?
set -e
[[ $rc -eq 6 ]] || { cat "$TMP/err2a.txt"; echo "FAIL test 2a: expected exit 6, got $rc"; exit 1; }
grep -q "skipping missing file" "$TMP/err2a.txt" \
  || { cat "$TMP/err2a.txt"; echo "FAIL test 2a: expected skip warning"; exit 1; }
echo "OK test 2a: missing file fails with exit 6 by default"

# --- Test 2b: --continue-on-error keeps going past missing file ---
: > "$BODY_DUMP"
CONFLUENCE_PASS=plainpassword python3 "$ATTACH" \
  --host "http://127.0.0.1:$PORT" \
  --user testuser \
  --page-id 999 \
  --continue-on-error \
  --files "$TMP/page/not-here.png" "$TMP/page/diagram.png" >"$TMP/out2b.txt" 2>"$TMP/err2b.txt" \
  || { cat "$TMP/out2b.txt" "$TMP/err2b.txt"; echo "FAIL test 2b: --continue-on-error should exit 0"; exit 1; }
grep -q "skipping missing file" "$TMP/err2b.txt" \
  || { cat "$TMP/err2b.txt"; echo "FAIL test 2b: expected skip warning"; exit 1; }
grep -q "Uploaded 1 attachment" "$TMP/err2b.txt" \
  || { cat "$TMP/err2b.txt"; echo "FAIL test 2b: expected 1 upload"; exit 1; }
echo "OK test 2b: --continue-on-error skips missing file and continues"

# --- Test 3: multipart correctness (re-run a fresh single-file upload) ---
: > "$BODY_DUMP"
CONFLUENCE_PASS=plainpassword python3 "$ATTACH" \
  --host "http://127.0.0.1:$PORT" \
  --user testuser \
  --page-id 999 \
  --files "$TMP/page/diagram.png" >/dev/null 2>"$TMP/err3.txt" \
  || { cat "$TMP/err3.txt"; echo "FAIL test 3: setup upload failed"; exit 1; }

grep -q "^X-Atlassian-Token: nocheck$" "$BODY_DUMP" \
  || { cat "$BODY_DUMP"; echo "FAIL test 3: missing X-Atlassian-Token header"; exit 1; }
grep -q 'multipart/form-data; boundary=' "$BODY_DUMP" \
  || { echo "FAIL test 3: missing multipart boundary"; exit 1; }
grep -q 'filename="diagram.png"' "$BODY_DUMP" \
  || { cat "$BODY_DUMP"; echo "FAIL test 3: filename not in multipart body"; exit 1; }
echo "OK test 3: multipart body has nocheck token, boundary, filename"

# --- Test 4: URL contains /content/<page-id>/child/attachment ---
grep -q "^PATH: /rest/api/content/999/child/attachment$" "$BODY_DUMP" \
  || { cat "$BODY_DUMP"; echo "FAIL test 4: page-id not in URL path"; exit 1; }
echo "OK test 4: upload URL contains /content/999/child/attachment"

echo ""
echo "All attach tests passed."
