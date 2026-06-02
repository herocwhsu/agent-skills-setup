# Fixtures

Real-page exports from your Confluence instance. The codec
(`lib/storage_codec.py`) is implemented against these. Synthetic XML
won't catch real-world quirks (CDATA wrapping, attribute ordering,
namespace inconsistencies across Confluence versions).

## How to export

```bash
source ~/.agent-skills-setup/lib.sh
load_config

SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
PASS=$(require_secret "$SLUG" "$CONFLUENCE_USER")

curl -fsS -u "$CONFLUENCE_USER:$PASS" \
  "https://$CONFLUENCE_HOST/rest/api/content/{PAGE_ID}?expand=body.storage" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["body"]["storage"]["value"])' \
  > skills/confluence/tests/fixtures/{NAME}.xml

unset PASS
```

## Required coverage

Pick one page each that exercises:

| Filename | What it must contain |
|---|---|
| `simple.xml` | Headings, paragraphs, ordered + unordered lists, bold/italic, inline links |
| `table.xml` | A markdown-representable table; bonus if it has merged cells |
| `code-macro.xml` | `<ac:structured-macro ac:name="code">` with a language attribute |
| `info-macro.xml` | `<ac:structured-macro ac:name="info">` (or `note`/`warning`) |
| `expand-macro.xml` | `<ac:structured-macro ac:name="expand">` |
| `image-attachment.xml` | `<ac:image><ri:attachment ri:filename="..."/></ac:image>` |
| `drawio.xml` | A drawio macro — exact `ac:name` varies by plugin (`drawio`, `drawio-board`, etc.) |
| `cross-page-link.xml` | `<ac:link><ri:page ri:content-title="..."/></ac:link>` |
| `mention.xml` | `<ac:link><ri:user ri:userkey="..."/></ac:link>` |
| `nested-list.xml` | A list 3+ levels deep — markdown's weakest spot |

If your instance doesn't have one of these, skip that fixture rather
than synthesize. The codec needs to fail loudly on unknown shapes, not
silently strip them, so a missing fixture is fine — the test matrix
just covers fewer cases.

## After exporting

`tests/test_codec_roundtrip.sh` iterates every `.xml` in this dir and
asserts decode → encode → decode is semantically equal. It's currently
skipped because the codec is a stub. Once the codec is implemented,
remove the skip guard.
