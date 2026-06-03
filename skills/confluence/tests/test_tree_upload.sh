#!/usr/bin/env bash
# test_tree_upload.sh — exercise tree_upload.py against a mock REST server.
#
# Covers:
#   1. happy path: 2 pages → 2 stub POSTs + 2 content PUTs, both new ids
#      appear on stderr, exit 0
#   2. wiki-link rewrite: a wiki://page/Child A in root.md becomes a
#      /pages/<new-child-id> URL in the PUT body for the root
#   3. stub failure aborts pass 2: second POST returns 500 → exit 6, error
#      mentions stubs-created-so-far, no PUT happens
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UPLOAD="$SKILL_DIR/lib/tree_upload.py"

TMP=$(mktemp -d)
SERVER_PIDS=()
cleanup() {
  for pid in "${SERVER_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

# ============================================================
# Build a tiny local tree once: root (#100) + child (#200).
# Reused across tests; tests only differ in mock-server behavior.
# ============================================================
build_tree() {
  local out="$1"
  rm -rf "$out"
  mkdir -p "$out"

  cat > "$out/_root.md" <<'MD'
---
source_page_id: "100"
source_title: "Root"
source_url: "http://example/Root"
source_version: 1
fetched_at: "2026-06-03"
---

Root body. Link to [Child A](wiki://page/Child%20A).
MD

  cat > "$out/child-a.md" <<'MD'
---
source_page_id: "200"
source_title: "Child A"
source_url: "http://example/Child+A"
source_version: 1
fetched_at: "2026-06-03"
---

Child body.
MD

  cat > "$out/manifest.json" <<'JSON'
{
  "root_id": "100",
  "root_title": "Root",
  "host": "example.com",
  "fetched_at": "2026-06-03",
  "pages": [
    {"page_id": "100", "title": "Root", "relative_path": "_root.md", "parent_id": null, "depth": 0},
    {"page_id": "200", "title": "Child A", "relative_path": "child-a.md", "parent_id": "100", "depth": 1}
  ]
}
JSON
}

# ============================================================
# Mock server template — records every request to a dump file.
# Behavior is governed by env var POST_BEHAVIOR ("ok" or "fail2").
#   ok    : both POSTs return {"id":"1000",...} then {"id":"2000",...}
#   fail2 : first POST → 1000, second POST → 500
# Every PUT echoes back the page id it was called with (always 200).
# Request log lines look like:
#   POST /rest/api/content
#   <body json>
#   PUT /rest/api/content/1000
#   <body json>
# ============================================================
write_server() {
  cat > "$TMP/server.py" <<'PYEOF'
import http.server, json, os, sys, threading

DUMP = os.environ["DUMP"]
BEHAVIOR = os.environ.get("POST_BEHAVIOR", "ok")
POST_COUNTER = {"n": 0}

def log(method, path, body):
    with open(DUMP, "ab") as f:
        f.write(f"{method} {path}\n".encode())
        f.write(body if body else b"")
        f.write(b"\n---END---\n")

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length else b""

    def do_POST(self):
        body = self._read_body()
        log("POST", self.path, body)
        POST_COUNTER["n"] += 1
        n = POST_COUNTER["n"]
        if BEHAVIOR == "fail2" and n == 2:
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"message":"boom"}')
            return
        # First post → 1000, second → 2000, etc.
        new_id = str(1000 * n)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "id": new_id,
            "version": {"number": 1},
            "title": "stub",
            "_links": {"webui": f"/display/X/{new_id}"},
        }).encode())

    def do_PUT(self):
        body = self._read_body()
        log("PUT", self.path, body)
        # Extract id from path
        page_id = self.path.rsplit("/", 1)[-1]
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "id": page_id, "version": {"number": 2}, "title": "x",
        }).encode())

port = int(os.environ["PORT"])
srv = http.server.HTTPServer(("127.0.0.1", port), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
sys.stdout.write("ready\n"); sys.stdout.flush()
import signal; signal.pause()
PYEOF
}

start_server() {
  local port="$1" dump="$2" behavior="$3"
  : > "$dump"
  PORT=$port DUMP=$dump POST_BEHAVIOR=$behavior \
    python3 "$TMP/server.py" >"$TMP/server.log" 2>&1 &
  local pid=$!
  SERVER_PIDS+=("$pid")
  disown "$pid" 2>/dev/null || true
  for _ in $(seq 1 30); do
    grep -q ready "$TMP/server.log" 2>/dev/null && break
    sleep 0.1
  done
  grep -q ready "$TMP/server.log" || { cat "$TMP/server.log"; echo "FAIL: server didn't start"; exit 1; }
  echo "$pid"
}

write_server
build_tree "$TMP/tree"

# ============================================================
# Test 1: happy path — 2 stubs created, 2 PUTs, both ids on stderr
# ============================================================
PORT1=$((45000 + RANDOM % 1000))
DUMP1="$TMP/dump1"
start_server "$PORT1" "$DUMP1" "ok" >/dev/null

CONFLUENCE_PASS=plainpass python3 "$UPLOAD" \
  --tree "$TMP/tree" \
  --new-parent 999 \
  --space PP2 \
  --host "http://127.0.0.1:$PORT1" \
  --user testuser >"$TMP/out1.txt" 2>"$TMP/err1.txt" \
  || { cat "$TMP/out1.txt" "$TMP/err1.txt"; echo "FAIL test 1: tree_upload exited non-zero"; exit 1; }

# Two stub POSTs → ids 1000 and 2000
post_count=$(grep -c '^POST /rest/api/content$' "$DUMP1" || true)
[[ $post_count -eq 2 ]] || { cat "$DUMP1"; echo "FAIL test 1: expected 2 POSTs, got $post_count"; exit 1; }

# Two PUTs (one per page)
put_count=$(grep -cE '^PUT /rest/api/content/[0-9]+$' "$DUMP1" || true)
[[ $put_count -eq 2 ]] || { cat "$DUMP1"; echo "FAIL test 1: expected 2 PUTs, got $put_count"; exit 1; }

grep -q "stub: Root → #1000" "$TMP/err1.txt" \
  || { cat "$TMP/err1.txt"; echo "FAIL test 1: missing 'stub: Root → #1000'"; exit 1; }
grep -q "stub: Child A → #2000" "$TMP/err1.txt" \
  || { cat "$TMP/err1.txt"; echo "FAIL test 1: missing 'stub: Child A → #2000'"; exit 1; }
grep -q "Done. Created 2 pages" "$TMP/err1.txt" \
  || { cat "$TMP/err1.txt"; echo "FAIL test 1: missing summary"; exit 1; }
echo "OK test 1: happy path — 2 stubs + 2 PUTs"

# ============================================================
# Test 2: wiki-link rewrite — root PUT body must contain /pages/2000
# ============================================================
# Reuses dump1 from test 1.
python3 - "$DUMP1" <<'PYEOF'
import re, sys
dump = open(sys.argv[1], "rb").read().decode("utf-8", errors="replace")
# Find the PUT to /rest/api/content/1000 (root) and check its body
m = re.search(r'^PUT /rest/api/content/1000\n(.+?)\n---END---', dump, re.M | re.S)
assert m, f"no PUT to root in dump:\n{dump}"
body = m.group(1)
# The wiki link must have been rewritten to .../pages/2000
assert "/pages/2000" in body, f"root PUT body missing /pages/2000:\n{body}"
assert "wiki://page/Child" not in body, f"root PUT body still has wiki:// link:\n{body}"
PYEOF
echo "OK test 2: wiki link rewrite — root PUT body contains /pages/2000"

# ============================================================
# Test 3: stub failure (second POST → 500) aborts before pass 2
# ============================================================
PORT3=$((46000 + RANDOM % 1000))
DUMP3="$TMP/dump3"
start_server "$PORT3" "$DUMP3" "fail2" >/dev/null

set +e
CONFLUENCE_PASS=plainpass python3 "$UPLOAD" \
  --tree "$TMP/tree" \
  --new-parent 999 \
  --space PP2 \
  --host "http://127.0.0.1:$PORT3" \
  --user testuser >"$TMP/out3.txt" 2>"$TMP/err3.txt"
rc=$?
set -e

[[ $rc -eq 6 ]] || { cat "$TMP/err3.txt"; echo "FAIL test 3: expected exit 6, got $rc"; exit 1; }
grep -q "Stubs created so far" "$TMP/err3.txt" \
  || { cat "$TMP/err3.txt"; echo "FAIL test 3: expected 'Stubs created so far' message"; exit 1; }

# No PUT should have been issued (pass 2 must not run).
if grep -qE '^PUT ' "$DUMP3"; then
  cat "$DUMP3"
  echo "FAIL test 3: PUT was issued despite stub failure — pass 2 ran"
  exit 1
fi
echo "OK test 3: stub failure aborts before pass 2 (no PUT)"

# ============================================================
# Test 4: --dry-run — no network calls, link resolution shown
# ============================================================
PORT4=$((47000 + RANDOM % 1000))
DUMP4="$TMP/dump4"
start_server "$PORT4" "$DUMP4" "ok" >/dev/null

# No CONFLUENCE_PASS needed for dry-run.
unset CONFLUENCE_PASS
python3 "$UPLOAD" \
  --tree "$TMP/tree" \
  --new-parent 999 \
  --space PP2 \
  --host "http://127.0.0.1:$PORT4" \
  --user testuser \
  --dry-run >"$TMP/out4.txt" 2>"$TMP/err4.txt" \
  || { cat "$TMP/out4.txt" "$TMP/err4.txt"; echo "FAIL test 4: dry-run exited non-zero"; exit 1; }

# Mock server should have received zero requests.
[[ ! -s "$DUMP4" ]] || { cat "$DUMP4"; echo "FAIL test 4: dry-run made network requests"; exit 1; }

grep -q "DRY RUN: would create 2 stubs" "$TMP/out4.txt" \
  || { cat "$TMP/out4.txt"; echo "FAIL test 4: missing dry-run banner"; exit 1; }
grep -q "would rewrite to source #200" "$TMP/out4.txt" \
  || { cat "$TMP/out4.txt"; echo "FAIL test 4: link resolution not shown"; exit 1; }
echo "OK test 4: --dry-run skips network and reports link resolution"

# ============================================================
# Test 5: attachment 500 warns and continues
#   POST /rest/api/content/<id>/child/attachment → 500
#   POST /rest/api/content (stub create)         → 200
#   PUT  /rest/api/content/<id>                  → 200
# Confirms upload exits 0, warning is logged, PUT is reached.
# ============================================================
cat > "$TMP/server5.py" <<'PYEOF'
import http.server, json, os, sys, threading

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length else b""

    def do_POST(self):
        self._read_body()
        if "child/attachment" in self.path:
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"message":"intentional fail"}')
            return
        # Stub create
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "id": "5000",
            "version": {"number": 1},
            "title": "stub",
            "_links": {"webui": "/display/X/5000"},
        }).encode())

    def do_PUT(self):
        self._read_body()
        with open(os.environ["PUT_FLAG"], "w") as f:
            f.write("yes")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "id": "5000", "version": {"number": 2}, "title": "x",
        }).encode())

port = int(os.environ["PORT"])
srv = http.server.HTTPServer(("127.0.0.1", port), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
sys.stdout.write("ready\n"); sys.stdout.flush()
import signal; signal.pause()
PYEOF

T5="$TMP/tree5"
mkdir -p "$T5/_root.attachments"
cat > "$T5/_root.md" <<'MD'
---
source_page_id: "500"
source_title: "Root5"
source_url: "http://example/Root5"
source_version: 1
fetched_at: "2026-06-03"
---

# Root5
MD
echo "binary" > "$T5/_root.attachments/blob.dat"
cat > "$T5/manifest.json" <<'JSON'
{
  "root_id": "500",
  "root_title": "Root5",
  "host": "example.com",
  "fetched_at": "2026-06-03",
  "pages": [
    {"page_id": "500", "title": "Root5", "relative_path": "_root.md", "parent_id": null, "depth": 0}
  ]
}
JSON

PORT5=$((49000 + RANDOM % 1000))
PUT_FLAG="$TMP/put5.flag"
PORT=$PORT5 PUT_FLAG=$PUT_FLAG python3 "$TMP/server5.py" >"$TMP/server5.log" 2>&1 &
SERVER5_PID=$!
SERVER_PIDS+=("$SERVER5_PID")
disown "$SERVER5_PID" 2>/dev/null || true
for _ in $(seq 1 30); do
  grep -q ready "$TMP/server5.log" 2>/dev/null && break
  sleep 0.1
done
grep -q ready "$TMP/server5.log" \
  || { cat "$TMP/server5.log"; echo "FAIL test 5: server didn't start"; exit 1; }

CONFLUENCE_PASS=plainpass python3 "$UPLOAD" \
  --tree "$T5" \
  --new-parent 999 \
  --space PP2 \
  --host "http://127.0.0.1:$PORT5" \
  --user testuser >"$TMP/out5.txt" 2>"$TMP/err5.txt" \
  || { cat "$TMP/out5.txt" "$TMP/err5.txt"; echo "FAIL test 5: upload should have exited 0 despite attachment 500"; exit 1; }

grep -q 'attachment upload failed' "$TMP/err5.txt" \
  || { cat "$TMP/err5.txt"; echo "FAIL test 5: expected attachment failure warning"; exit 1; }
[[ -f "$PUT_FLAG" ]] \
  || { cat "$TMP/err5.txt"; echo "FAIL test 5: PUT was not reached"; exit 1; }
echo "OK test 5: attachment 500 warns and continues, PUT still reached"

echo ""
echo "All tree_upload tests passed."
