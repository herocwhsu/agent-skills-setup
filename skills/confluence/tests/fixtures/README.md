# Fixtures

Real-page exports from your Confluence instance. The XHTML-to-markdown
converter (`lib/xhtml_to_md.py`) and the markdown-to-XHTML converter
(`lib/md_to_xhtml.py`) are implemented against these samples. Synthetic
XML won't catch real-world quirks (CDATA wrapping, attribute ordering,
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
| `code-macro.xml` | `<ac:structured-macro ac:name="code">` with a language attribute |
| `info-macro.xml` | `<ac:structured-macro ac:name="info">` (or `note`/`warning`) |
| `image-attachment.xml` | `<ac:image><ri:attachment ri:filename="..."/></ac:image>` |
| `drawio.xml` | A drawio macro — exact `ac:name` varies by plugin (`drawio`, `drawio-board`, etc.) |
| `cross-page-link.xml` | `<ac:link><ri:page ri:content-title="..."/></ac:link>` |

If your instance doesn't have one of these, skip that fixture rather
than synthesize. The converter needs to fail loudly on unknown shapes,
not silently strip them, so a missing fixture is fine — the test
matrix just covers fewer cases.

## After exporting

`tests/test_xhtml_to_md.sh` (lands in Task 2) iterates every `.xml` in
this directory and asserts the converter produces the expected
markdown for each fixture.
