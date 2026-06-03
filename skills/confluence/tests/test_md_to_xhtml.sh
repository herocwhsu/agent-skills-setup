#!/usr/bin/env bash
# tests/test_md_to_xhtml.sh
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$SKILL_DIR/lib/md_to_xhtml.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: simple markdown round-trips through to XHTML basics ---
cat > "$TMP/in.md" <<'MD'
---
source_page_id: "111"
source_title: "T"
---

# Title

Hello **world**.

- a
- b
MD
python3 "$CONV" --md-file "$TMP/in.md" --out "$TMP/out.xml"
grep -q '<h1>Title</h1>' "$TMP/out.xml" || { cat "$TMP/out.xml"; echo "FAIL test 1 heading"; exit 1; }
grep -q '<strong>world</strong>' "$TMP/out.xml" || { echo "FAIL test 1 bold"; exit 1; }
grep -q '<ul><li>a</li><li>b</li></ul>' "$TMP/out.xml" || { echo "FAIL test 1 list"; exit 1; }
echo "OK test 1"

# --- Test 2: code fence becomes ac:structured-macro code ---
cat > "$TMP/code.md" <<'MD'
```go
fmt.Println("hi")
```
MD
python3 "$CONV" --md-file "$TMP/code.md" --out "$TMP/code.xml"
grep -q 'ac:name="code"' "$TMP/code.xml" || { cat "$TMP/code.xml"; echo "FAIL test 2"; exit 1; }
grep -q 'ac:name="language">go' "$TMP/code.xml" || { echo "FAIL test 2 lang"; exit 1; }
echo "OK test 2"

# --- Test 3: diagram placeholder + sidecar restores macro ---
cat > "$TMP/d.md" <<'MD'
Before.

<!-- diagram:d1 -->

After.
MD
cat > "$TMP/d.diagrams.json" <<'JSON'
{"d1": {"type": "drawio", "xml": "<ac:structured-macro ac:name=\"drawio\" ac:macro-id=\"abc\"><ac:parameter ac:name=\"diagramName\">arch</ac:parameter></ac:structured-macro>"}}
JSON
python3 "$CONV" --md-file "$TMP/d.md" --diagrams-file "$TMP/d.diagrams.json" --out "$TMP/d.xml"
grep -q 'ac:name="drawio"' "$TMP/d.xml" || { cat "$TMP/d.xml"; echo "FAIL test 3"; exit 1; }
grep -q 'ac:macro-id="abc"' "$TMP/d.xml" || { echo "FAIL test 3 id lost"; exit 1; }
echo "OK test 3"

# --- Test 4: image link becomes ac:image with ri:attachment ---
cat > "$TMP/img.md" <<'MD'
![alt](./_index.attachments/diagram.png)
MD
python3 "$CONV" --md-file "$TMP/img.md" --out "$TMP/img.xml"
grep -q '<ac:image' "$TMP/img.xml" || { cat "$TMP/img.xml"; echo "FAIL test 4 image"; exit 1; }
grep -q 'ri:filename="diagram.png"' "$TMP/img.xml" || { echo "FAIL test 4 filename"; exit 1; }
echo "OK test 4"

# --- Test 5: blockquote with **Info:** prefix becomes info macro ---
cat > "$TMP/info.md" <<'MD'
> **Info:** be careful
MD
python3 "$CONV" --md-file "$TMP/info.md" --out "$TMP/info.xml"
grep -q 'ac:name="info"' "$TMP/info.xml" || { cat "$TMP/info.xml"; echo "FAIL test 5"; exit 1; }
echo "OK test 5"

# --- Test 6: wiki:// link with no rewrite map keeps as plain text + URL ---
cat > "$TMP/wiki.md" <<'MD'
See [Other](wiki://page/Other Page).
MD
python3 "$CONV" --md-file "$TMP/wiki.md" --out "$TMP/wiki.xml"
# unresolved wiki:// links go through as plain anchor with the wiki:// URL — link_rewrite.py is responsible for resolving before push
grep -q 'wiki://page/Other Page' "$TMP/wiki.xml" || { cat "$TMP/wiki.xml"; echo "FAIL test 6"; exit 1; }
echo "OK test 6"

echo ""
echo "All md_to_xhtml tests passed."
