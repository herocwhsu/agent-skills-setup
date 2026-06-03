#!/usr/bin/env bash
# Convert known-shape XHTML snippets and assert markdown output matches.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$SKILL_DIR/lib/xhtml_to_md.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: simple paragraph + heading + bold ---
cat > "$TMP/simple.xml" <<'XML'
<h1>Title</h1>
<p>Hello <strong>world</strong>.</p>
<ul><li>one</li><li>two</li></ul>
XML
python3 "$CONV" --input "$TMP/simple.xml" --out-md "$TMP/simple.md"
grep -q "^# Title$" "$TMP/simple.md" || { echo "FAIL test 1: missing title"; exit 1; }
grep -q '\*\*world\*\*' "$TMP/simple.md" || { echo "FAIL test 1: missing bold"; exit 1; }
grep -q '^- one$' "$TMP/simple.md" || { echo "FAIL test 1: missing list item"; exit 1; }
echo "OK test 1"

# --- Test 2: info macro becomes blockquote ---
cat > "$TMP/info.xml" <<'XML'
<ac:structured-macro ac:name="info">
  <ac:rich-text-body><p>Heads up.</p></ac:rich-text-body>
</ac:structured-macro>
XML
python3 "$CONV" --input "$TMP/info.xml" --out-md "$TMP/info.md"
grep -q '^> \*\*Info:\*\*' "$TMP/info.md" || { cat "$TMP/info.md"; echo "FAIL test 2"; exit 1; }
echo "OK test 2"

# --- Test 3: code macro keeps language ---
cat > "$TMP/code.xml" <<'XML'
<ac:structured-macro ac:name="code">
  <ac:parameter ac:name="language">go</ac:parameter>
  <ac:plain-text-body><![CDATA[fmt.Println("hi")]]></ac:plain-text-body>
</ac:structured-macro>
XML
python3 "$CONV" --input "$TMP/code.xml" --out-md "$TMP/code.md"
grep -q '^```go$' "$TMP/code.md" || { cat "$TMP/code.md"; echo "FAIL test 3"; exit 1; }
grep -q 'fmt.Println' "$TMP/code.md" || { echo "FAIL test 3: body missing"; exit 1; }
echo "OK test 3"

# --- Test 4: drawio macro becomes placeholder + sidecar ---
cat > "$TMP/drawio.xml" <<'XML'
<ac:structured-macro ac:name="drawio" ac:macro-id="abc-123">
  <ac:parameter ac:name="diagramName">arch</ac:parameter>
</ac:structured-macro>
XML
python3 "$CONV" --input "$TMP/drawio.xml" --out-md "$TMP/drawio.md" --out-diagrams "$TMP/drawio.diagrams.json"
grep -q '<!-- diagram:d1 -->' "$TMP/drawio.md" || { cat "$TMP/drawio.md"; echo "FAIL test 4: placeholder"; exit 1; }
python3 -c "
import json
d = json.load(open('$TMP/drawio.diagrams.json'))
assert 'd1' in d, 'd1 missing in sidecar'
assert d['d1']['type'] == 'drawio'
assert 'ac:macro-id=\"abc-123\"' in d['d1']['xml']
"
echo "OK test 4"

# --- Test 5: image attachment becomes ./<dir>/<filename> ---
cat > "$TMP/image.xml" <<'XML'
<p>See <ac:image><ri:attachment ri:filename="diagram.png"/></ac:image></p>
XML
python3 "$CONV" --input "$TMP/image.xml" --out-md "$TMP/image.md" --attachments-rel "./_index.attachments"
grep -q '!\[\](\./_index\.attachments/diagram\.png)' "$TMP/image.md" || { cat "$TMP/image.md"; echo "FAIL test 5"; exit 1; }
echo "OK test 5"

# --- Test 6: ac:link to another page becomes URL placeholder with source_page_id ---
cat > "$TMP/link.xml" <<'XML'
<p>See <ac:link><ri:page ri:content-title="Other Page"/><ac:plain-text-link-body><![CDATA[Other]]></ac:plain-text-link-body></ac:link></p>
XML
python3 "$CONV" --input "$TMP/link.xml" --out-md "$TMP/link.md" --base-url "https://confluence.example.com"
# Page-link-by-title preserves the title in a wiki:// URL the rewriter understands
grep -q '\[Other\](wiki://page/Other Page)' "$TMP/link.md" || { cat "$TMP/link.md"; echo "FAIL test 6"; exit 1; }
echo "OK test 6"

echo ""
echo "All xhtml_to_md tests passed."
