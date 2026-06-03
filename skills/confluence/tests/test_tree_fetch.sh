#!/usr/bin/env bash
# test_tree_fetch.sh — exercise tree_fetch.py against a mock REST server.
#
# Covers:
#   1. root markdown saved with frontmatter (page id 100, title "Root", body)
#   2. attachment downloaded under <root>.attachments/
#   3. child page saved as leaf (Child A, page id 200)
#   4. manifest.json shape (root + child, parent_id, depth)
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FETCH="$SKILL_DIR/lib/tree_fetch.py"

TMP=$(mktemp -d)
trap '[[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

# --- Mock server ---
cat > "$TMP/server.py" <<'PYEOF'
import http.server, json, os, sys, threading

PAGES = {
    "100": {
        "id": "100", "title": "Root", "version": {"number": 5},
        "space": {"key": "PP2"}, "ancestors": [],
        "body": {"storage": {"value": "<p>root content</p>", "representation": "storage"}},
        "_links": {"webui": "/display/PP2/Root"},
    },
    "200": {
        "id": "200", "title": "Child A", "version": {"number": 3},
        "space": {"key": "PP2"}, "ancestors": [{"id": "100"}],
        "body": {"storage": {"value": "<p>child body</p>", "representation": "storage"}},
        "_links": {"webui": "/display/PP2/Child+A"},
    },
}
CHILDREN = {"100": ["200"], "200": []}
ATTACHMENTS = {
    "100": [{"id": "att1", "title": "diagram.png", "extensions": {"fileSize": 100},
            "_links": {"download": "/download/100/diagram.png"}}],
    "200": [],
}
ATTACH_BYTES = {"/download/100/diagram.png": b"fake-png-bytes"}

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ATTACH_BYTES:
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.end_headers()
            self.wfile.write(ATTACH_BYTES[path])
            return
        for pid, body in PAGES.items():
            if path == f"/rest/api/content/{pid}":
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())
                return
            if path == f"/rest/api/content/{pid}/child/page":
                results = [PAGES[c] for c in CHILDREN[pid]]
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(
                    {"results": results, "size": len(results), "_links": {}}
                ).encode())
                return
            if path == f"/rest/api/content/{pid}/child/attachment":
                results = ATTACHMENTS[pid]
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(
                    {"results": results, "size": len(results), "_links": {}}
                ).encode())
                return
        self.send_response(404)
        self.end_headers()

port = int(os.environ["PORT"])
srv = http.server.HTTPServer(("127.0.0.1", port), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
sys.stdout.write("ready\n"); sys.stdout.flush()
import signal; signal.pause()
PYEOF

PORT=$((42000 + RANDOM % 1000))
PORT=$PORT python3 "$TMP/server.py" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 30); do
  grep -q ready "$TMP/server.log" 2>/dev/null && break
  sleep 0.1
done
grep -q ready "$TMP/server.log" || { cat "$TMP/server.log"; echo "FAIL: server didn't start"; exit 1; }

OUT="$TMP/out"
CONFLUENCE_PASS=plainpass python3 "$FETCH" \
  --host "http://127.0.0.1:$PORT" \
  --user testuser \
  --root-id 100 \
  --out-dir "$OUT" >"$TMP/run.log" 2>&1 \
  || { cat "$TMP/run.log"; echo "FAIL: fetch exited non-zero"; exit 1; }

# --- Test 1: root markdown + frontmatter ---
[[ -f "$OUT/_root.md" ]] || { ls -la "$OUT" 2>/dev/null; echo "FAIL test 1: _root.md missing"; exit 1; }
grep -q '^source_page_id: "100"$' "$OUT/_root.md" \
  || { cat "$OUT/_root.md"; echo "FAIL test 1: source_page_id wrong"; exit 1; }
grep -q '^source_title: "Root"$' "$OUT/_root.md" \
  || { cat "$OUT/_root.md"; echo "FAIL test 1: source_title wrong"; exit 1; }
grep -q 'root content' "$OUT/_root.md" \
  || { cat "$OUT/_root.md"; echo "FAIL test 1: body missing"; exit 1; }
echo "OK test 1: root markdown saved with frontmatter"

# --- Test 2: attachment downloaded ---
[[ -f "$OUT/_root.attachments/diagram.png" ]] \
  || { ls -la "$OUT/_root.attachments" 2>/dev/null; echo "FAIL test 2: attachment missing"; exit 1; }
[[ "$(cat "$OUT/_root.attachments/diagram.png")" == "fake-png-bytes" ]] \
  || { echo "FAIL test 2: attachment bytes wrong"; exit 1; }
echo "OK test 2: attachment downloaded"

# --- Test 3: child page saved as leaf ---
CHILD_FILE=$(find "$OUT" -name '*.md' -not -name '_root.md' -not -name '_index.md' | head -1)
[[ -n "$CHILD_FILE" ]] || { find "$OUT"; echo "FAIL test 3: no child .md found"; exit 1; }
grep -q '^source_page_id: "200"$' "$CHILD_FILE" \
  || { cat "$CHILD_FILE"; echo "FAIL test 3: child source_page_id wrong"; exit 1; }
echo "OK test 3: child page saved"

# --- Test 4: manifest.json shape ---
[[ -f "$OUT/manifest.json" ]] || { echo "FAIL test 4: manifest missing"; exit 1; }
python3 -c "
import json
m = json.load(open('$OUT/manifest.json'))
assert m['root_id'] == '100', m
assert len(m['pages']) == 2, m
ids = {p['page_id']: p for p in m['pages']}
assert ids['100']['parent_id'] is None
assert ids['100']['depth'] == 0
assert ids['200']['parent_id'] == '100'
assert ids['200']['depth'] == 1
"
echo "OK test 4: manifest has both pages with correct parent/depth"

echo ""
echo "All tree_fetch tests passed."
