#!/usr/bin/env bash
# tests/test_link_rewrite.sh
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LR="$SKILL_DIR/lib/link_rewrite.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/tree/child"
cat > "$TMP/tree/_root.md" <<'MD'
---
source_page_id: "100"
source_title: "Root"
---

See [Child A](wiki://page/Child A) and [Outside](wiki://page/Outside).
MD
cat > "$TMP/tree/child/_index.md" <<'MD'
---
source_page_id: "200"
source_title: "Child A"
---

# Child A

Hello.
MD

# --- Test 1: build-map JSON contains both pages ---
python3 "$LR" build-map --tree "$TMP/tree" --out "$TMP/map.json"
python3 -c "
import json
m = json.load(open('$TMP/map.json'))
assert m['100']['relative_path'].endswith('_root.md'), m
assert m['100']['title'] == 'Root', m
assert m['200']['title'] == 'Child A', m
assert m['200']['relative_path'].endswith('child/_index.md'), m
"
echo "OK test 1"

# --- Test 2: rewrite resolves intra-tree, leaves outside link unchanged ---
python3 "$LR" rewrite --md-file "$TMP/tree/_root.md" --map "$TMP/map.json"
grep -q '\[Child A\](\./child/_index\.md)' "$TMP/tree/_root.md" \
  || { cat "$TMP/tree/_root.md"; echo "FAIL test 2: child link not rewritten"; exit 1; }
grep -q '\[Outside\](wiki://page/Outside)' "$TMP/tree/_root.md" \
  || { echo "FAIL test 2: outside link should pass through"; exit 1; }
echo "OK test 2"

# --- Test 3: URL-encoded titles (with parens) match decoded titles in the map ---
mkdir -p "$TMP/tree2"
cat > "$TMP/tree2/_root.md" <<'MD'
---
source_page_id: "300"
source_title: "Root 2"
---

See [the page](wiki://page/Foo %28bar%29).
MD
cat > "$TMP/tree2/foo.md" <<'MD'
---
source_page_id: "400"
source_title: "Foo (bar)"
---

# Foo (bar)
MD
python3 "$LR" build-map --tree "$TMP/tree2" --out "$TMP/map2.json"
python3 "$LR" rewrite --md-file "$TMP/tree2/_root.md" --map "$TMP/map2.json"
grep -q '\[the page\](\./foo\.md)' "$TMP/tree2/_root.md" \
  || { cat "$TMP/tree2/_root.md"; echo "FAIL test 3: URL-encoded title with parens not rewritten"; exit 1; }
echo "OK test 3"

echo ""
echo "All link_rewrite tests passed."
