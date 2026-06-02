#!/usr/bin/env bash
# test_codec_roundtrip.sh — assert decode → encode → decode is
# semantically equal for every fixture under tests/fixtures/.
#
# SKIPPED while lib/storage_codec.py is a stub. Once the codec is
# implemented (plan tasks 1+2), the SKIP guard becomes a real test.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CODEC="$SKILL_DIR/lib/storage_codec.py"

# Skip guard: codec stub raises NotImplementedError. When the real
# codec lands, decode of an empty fixture should not raise.
if python3 "$CODEC" decode --input /dev/null --out-md /dev/null --out-meta /dev/null 2>&1 | grep -q "not yet implemented"; then
  echo "SKIP: storage_codec.py is a stub (see plan task 1+2)"
  exit 0
fi

FIXTURES="$SKILL_DIR/tests/fixtures"
shopt -s nullglob
fixtures=("$FIXTURES"/*.xml)

if [[ ${#fixtures[@]} -eq 0 ]]; then
  echo "SKIP: no fixtures in $FIXTURES (see fixtures/README.md)"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for fx in "${fixtures[@]}"; do
  name=$(basename "$fx" .xml)
  echo "  → $name"
  python3 "$CODEC" decode --input "$fx" \
                          --out-md "$TMP/$name.md" \
                          --out-meta "$TMP/$name.meta.json"
  python3 "$CODEC" encode --md-file "$TMP/$name.md" \
                          --meta-file "$TMP/$name.meta.json" \
                          --out "$TMP/$name.roundtrip.xml"
  python3 "$CODEC" decode --input "$TMP/$name.roundtrip.xml" \
                          --out-md "$TMP/$name.2.md" \
                          --out-meta "$TMP/$name.2.meta.json"
  diff -u "$TMP/$name.md" "$TMP/$name.2.md" \
    || { echo "FAIL: $name md not stable across roundtrip"; exit 1; }
done

echo ""
echo "All codec roundtrip tests passed."
