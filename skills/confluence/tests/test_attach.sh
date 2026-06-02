#!/usr/bin/env bash
# test_attach.sh — exercise attach.py against a mock attachment endpoint.
#
# Covers:
#   1. local image upload: md rewritten to [ri:imgN], meta gains anchor
#   2. http:// URLs in markdown ignored
#   3. missing local file warns and skips, doesn't fail the run
#   4. multipart body has correct boundary + filename + X-Atlassian-Token
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ATTACH="$SKILL_DIR/lib/attach.py"

TMP=$(mktemp -d)
trap '[[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

# Mock server records request body to a file and replies 200.
cat > "$TMP/server.py" <<'PYEOF'
import http.server, json, os, sys, threading

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        with open(os.environ["BODY_DUMP"], "ab") as f:
            f.write(b"=== request ===\n")
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

# Set up md file with: 1 local image, 1 http image (should be ignored), 1 missing local image
mkdir "$TMP/page"
echo "fake png" > "$TMP/page/diagram.png"

cat > "$TMP/page/page.md" <<MDEOF
# Test page

![real](./diagram.png)

![remote ignored](https://example.com/remote.png)

![missing](./not-here.png)
MDEOF

cat > "$TMP/page/page.meta.json" <<EOF
{"pageId":"999","version":12,"space":"PP2","ancestor":"100","title":"Test","host":"http://127.0.0.1:$PORT","anchors":{}}
EOF

# --- Run ---
CONFLUENCE_PASS=plainpassword python3 "$ATTACH" \
  --md-file "$TMP/page/page.md" \
  --meta-file "$TMP/page/page.meta.json" \
  --host "http://127.0.0.1:$PORT" \
  --user testuser >"$TMP/out.txt" 2>&1 \
  || { cat "$TMP/out.txt"; echo "FAIL: attach exited non-zero"; exit 1; }

# --- Test 1: md rewritten ---
grep -q '!\[real\]\[ri:img1\]' "$TMP/page/page.md" \
  || { cat "$TMP/page/page.md"; echo "FAIL test 1: md not rewritten with anchor"; exit 1; }
echo "OK test 1: local image reference rewritten to [ri:img1]"

# --- Test 2: http url left alone ---
grep -q '!\[remote ignored\](https://example.com/remote.png)' "$TMP/page/page.md" \
  || { echo "FAIL test 2: http URL was rewritten"; exit 1; }
echo "OK test 2: http:// URL left untouched"

# --- Test 3: missing file warned + skipped ---
grep -q "skipping missing file" "$TMP/out.txt" \
  || { cat "$TMP/out.txt"; echo "FAIL test 3: expected skip warning"; exit 1; }
grep -q '!\[missing\](./not-here.png)' "$TMP/page/page.md" \
  || { echo "FAIL test 3: missing file ref shouldn't be rewritten"; exit 1; }
echo "OK test 3: missing local file warned, md unchanged for that ref"

# --- Test 4: multipart correctness ---
grep -q "^X-Atlassian-Token: nocheck$" "$BODY_DUMP" \
  || { cat "$BODY_DUMP"; echo "FAIL test 4: missing X-Atlassian-Token header"; exit 1; }
grep -q 'multipart/form-data; boundary=' "$BODY_DUMP" \
  || { echo "FAIL test 4: missing multipart boundary"; exit 1; }
grep -q 'filename="diagram.png"' "$BODY_DUMP" \
  || { cat "$BODY_DUMP"; echo "FAIL test 4: filename not in multipart body"; exit 1; }
echo "OK test 4: multipart body has nocheck token, boundary, filename"

# --- Test 5: meta anchors updated ---
python3 -c "
import json
m = json.load(open('$TMP/page/page.meta.json'))
assert 'img1' in m['anchors'], 'img1 anchor missing'
assert m['anchors']['img1']['type'] == 'image'
assert m['anchors']['img1']['filename'] == 'diagram.png'
assert 'ri:filename=\"diagram.png\"' in m['anchors']['img1']['xml']
"
echo "OK test 5: meta.anchors.img1 populated"

echo ""
echo "All attach tests passed."
