# Confluence Migration Skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `skills/confluence/` from a round-trip editor into a one-way migration tool: fetch a source page tree, edit/reorganize locally, upload as a new page tree under a different parent.

**Architecture:** Lossy XHTML → readable markdown for fetch (with per-page diagram sidecar for drawio/Gliffy only), markdown → storage format for upload, intra-tree link rewriting via `source_page_id` frontmatter. Cross-page references resolve by walking a manifest built during a two-pass upload (stubs first, content second).

**Tech Stack:** Python 3 stdlib + lxml, bash for skill workflow, Confluence Server/DC REST API.

**Spec source:** Conversation 2026-06-02/03 — "migrate tool: catch from somewhere and translate to md, push to somewhere" with macros flattened (info/warn/code/expand) but drawio/Gliffy preserved as opaque sidecar entries the user edits in Confluence post-upload.

**Replaces:** `docs/superpowers/plans/2026-06-02-confluence-skill.md` (round-trip design — kept in git history, no longer authoritative).

---

## File structure

```
skills/confluence/
├── SKILL.md                    REWRITE — three subcommands: tree-fetch, tree-upload, link-rewrite-preview
├── README.md                   REWRITE — new flow, frontmatter contract
├── charter.md                  REWRITE — migration norms, not round-trip rules
├── lib/
│   ├── xhtml_to_md.py          NEW   — lossy converter: storage XHTML → md + per-page diagram sidecar
│   ├── md_to_xhtml.py          NEW   — markdown → storage XHTML (rebuilds <ac:image>, splices diagrams from sidecar)
│   ├── tree_fetch.py           NEW   — walk source tree, save md tree, download attachments
│   ├── link_rewrite.py         NEW   — build source_page_id→new_id map, rewrite intra-tree links
│   ├── tree_upload.py          NEW   — two-pass: stub all pages, then fill content
│   ├── push.py                 KEEP  — small simplification (drop unused update path)
│   └── attach.py               REVISE — emit <ac:image> reference; drop [ri:imgN] anchor rewrite
│   └── storage_codec.py        DELETE
└── tests/
    ├── fixtures/
    │   ├── README.md           UPDATE — fixture list shifts (no need for round-trip integrity samples)
    │   └── *.xml               (still required from real instance)
    ├── test_xhtml_to_md.sh     NEW
    ├── test_md_to_xhtml.sh     NEW
    ├── test_link_rewrite.sh    NEW
    ├── test_tree_fetch.sh      NEW   — uses mock REST server like existing test_push_conflict.sh
    ├── test_tree_upload.sh     NEW
    ├── test_push.sh            RENAME from test_push_conflict.sh; trim to create-only
    ├── test_attach.sh          KEEP, adjust assertions for new rewrite shape
    └── test_codec_roundtrip.sh DELETE
```

**Output layout produced by the skill** under the user's CWD:

```
docs/confluence-trees/<date>-<source-slug>/
├── manifest.json              Source-side metadata: tree shape, page IDs, attachment list
├── _root.md                   Source root page (with frontmatter: source_page_id, source_url, etc.)
├── _root.attachments/
│   └── <filename>             Files downloaded from source page's attachments
├── _root.diagrams.json        Per-page sidecar (drawio/Gliffy XML), only present when needed
├── child-page-a/
│   ├── _index.md
│   ├── _index.attachments/
│   └── _index.diagrams.json
└── child-page-b/
    └── _index.md
```

**Frontmatter on every fetched .md:**

```yaml
---
source_page_id: "12345678"
source_title: "VADP work / setup notes"
source_url: "https://confluence.example.com/display/RD/VADP-work"
source_version: 42
fetched_at: "2026-06-03"
attachments_dir: "./_root.attachments"  # relative path; only set if attachments exist
diagrams_file: "./_root.diagrams.json"  # only set if diagrams exist
---
```

The `source_page_id` is the load-bearing field — it's how `link_rewrite.py` resolves intra-tree links.

---

## Task 1: Replace scaffolding (SKILL.md, README, charter, delete codec)

**Files:**
- Modify: `skills/confluence/SKILL.md`
- Modify: `skills/confluence/README.md`
- Modify: `skills/confluence/charter.md`
- Delete: `skills/confluence/lib/storage_codec.py`
- Delete: `skills/confluence/tests/test_codec_roundtrip.sh`

- [ ] **Step 1: Rewrite SKILL.md frontmatter + body**

```yaml
---
name: confluence
description: Use when the user wants to migrate a Confluence page tree to a new location. Fetches a source page and all descendants as markdown, lets the user edit locally, then uploads the tree under a different parent page. Drawio/Gliffy diagrams preserved as opaque blocks; other macros flattened. Self-hosted Server/DC only.
---
```

Body sections required (write each in full — no placeholders):

1. `## Overview` — three-step flow (fetch → edit → upload), one paragraph
2. `## Subcommands` table — `/confluence-tree-fetch <page-id>`, `/confluence-tree-upload <local-dir> --parent <id> --space <KEY>`, `/confluence-link-rewrite-preview <local-dir> --parent <id>`
3. `## Frontmatter contract` — exact YAML block from "File structure" section above; rule: never edit `source_page_id` by hand
4. `## Diagram sidecar contract` — explain drawio/Gliffy preserved verbatim; user edits in Confluence after upload
5. `## Auth` — same as before (Basic Auth default, PAT auto-detect)
6. `## Workflow: tree-fetch` — 6 numbered steps invoking `lib/tree_fetch.py`
7. `## Workflow: tree-upload` — 5 numbered steps invoking `lib/link_rewrite.py` then `lib/tree_upload.py`
8. `## Workflow: link-rewrite-preview` — dry run that shows what would be rewritten
9. `## Common Mistakes` — table of 8 common errors

- [ ] **Step 2: Rewrite README.md**

Sections: Status, Install, Prerequisites, Subcommands table, Output Location example, Auth, Why this is separate from `fetch-page-to-markdown` and `fetch-jira-story`, Troubleshooting.

- [ ] **Step 3: Rewrite charter.md**

Migration-specific gotchas:
- Storage format: macros flatten lossy; only drawio/Gliffy preserved
- Manifest integrity: `manifest.json` must match the on-disk tree before upload; agent re-builds it on upload start
- Two-pass upload: stub creation must complete before content pass; partial stub failure aborts the whole upload
- Attachment names must be unique per destination page; use destination filename = source filename to keep markdown image refs stable
- Cross-tree links rewrite ONLY when target source_page_id is in the local tree

- [ ] **Step 4: Delete the obsolete codec stub and round-trip test**

```bash
rm skills/confluence/lib/storage_codec.py
rm skills/confluence/tests/test_codec_roundtrip.sh
```

- [ ] **Step 5: Commit**

```bash
git add skills/confluence/SKILL.md skills/confluence/README.md skills/confluence/charter.md
git rm skills/confluence/lib/storage_codec.py skills/confluence/tests/test_codec_roundtrip.sh
git commit -m "refactor(confluence): pivot from round-trip to migration tool"
```

---

## Task 2: `xhtml_to_md.py` — lossy converter (XHTML → md + diagram sidecar)

**Files:**
- Create: `skills/confluence/lib/xhtml_to_md.py`
- Create: `skills/confluence/tests/test_xhtml_to_md.sh`

The converter reads either Confluence REST JSON or raw .xml, emits markdown to one path and (when diagrams present) a JSON sidecar to another path. No round-trip guarantees — purely fetch-side.

- [ ] **Step 1: Write the failing test**

Create `tests/test_xhtml_to_md.sh`:

```bash
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
```

```bash
chmod +x skills/confluence/tests/test_xhtml_to_md.sh
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash skills/confluence/tests/test_xhtml_to_md.sh`
Expected: FAIL on test 1 ("xhtml_to_md.py: No such file or directory" or NotImplementedError).

- [ ] **Step 3: Implement `xhtml_to_md.py`**

```python
#!/usr/bin/env python3
"""xhtml_to_md.py — convert Confluence storage XHTML to readable markdown.

Lossy by design. Macros flatten:
    info/warning/note      → blockquote with bold prefix
    code (with language)   → fenced code block
    expand                 → bold title + body
    drawio / drawio-board  → placeholder <!-- diagram:dN --> + sidecar JSON
    gliffy                 → same as drawio
    other ac:* macros      → <!-- macro:<name> --> placeholder (best-effort, no sidecar)
ac:image with ri:attachment becomes a markdown image with --attachments-rel/<filename>.
ac:link with ri:page becomes [text](wiki://page/<title>) — link_rewrite.py resolves later.
ac:link with ri:user becomes plain text @<userkey>.

Usage:
    python3 xhtml_to_md.py --input page.xml --out-md out.md
                           [--out-diagrams out.diagrams.json]
                           [--attachments-rel ./_index.attachments]
                           [--base-url https://...]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

try:
    from lxml import etree
except ImportError:
    print("ERROR: lxml required. Install with: pip3 install lxml", file=sys.stderr)
    sys.exit(2)

NS = {
    "ac": "http://example.org/ac",  # Confluence storage uses bare ac:, ri: — we add these via wrapping
    "ri": "http://example.org/ri",
}

DRAWIO_MACROS = {"drawio", "drawio-board", "drawio-mxgraph", "gliffy"}
ADMONITION_MACROS = {"info": "Info", "warning": "Warning", "note": "Note", "tip": "Tip"}


def wrap_with_ns(xhtml: str) -> str:
    """Wrap a fragment with explicit namespace declarations so lxml can parse it."""
    return (
        '<root xmlns:ac="http://example.org/ac" xmlns:ri="http://example.org/ri">'
        f"{xhtml}"
        "</root>"
    )


def load_xhtml(path: str) -> str:
    raw = Path(path).read_text(encoding="utf-8")
    # If input is REST JSON, extract body.storage.value
    if raw.lstrip().startswith("{"):
        data = json.loads(raw)
        return data["body"]["storage"]["value"]
    return raw


def convert(xhtml: str, *, attachments_rel: str | None, base_url: str | None) -> tuple[str, dict]:
    """Return (markdown, diagrams_dict). diagrams_dict is empty if no diagrams seen."""
    diagrams: dict[str, dict] = {}
    diagram_counter = [0]

    def next_diag_id() -> str:
        diagram_counter[0] += 1
        return f"d{diagram_counter[0]}"

    tree = etree.fromstring(wrap_with_ns(xhtml))
    return _render(tree, diagrams, next_diag_id, attachments_rel, base_url).strip() + "\n", diagrams


def _render(node, diagrams, next_id, attachments_rel, base_url) -> str:
    out: list[str] = []
    tag = etree.QName(node).localname if node.tag is not etree.Comment else None

    if node.tag is etree.Comment:
        return ""

    if tag == "root":
        for child in node:
            out.append(_render(child, diagrams, next_id, attachments_rel, base_url))
        if node.text:
            out.insert(0, node.text)
        return "".join(out)

    if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
        level = int(tag[1])
        body = _inline(node, diagrams, next_id, attachments_rel, base_url)
        return f"\n{'#' * level} {body}\n\n"

    if tag == "p":
        body = _inline(node, diagrams, next_id, attachments_rel, base_url)
        return f"{body}\n\n" if body.strip() else ""

    if tag in {"ul", "ol"}:
        return _render_list(node, ordered=(tag == "ol"), depth=0,
                            diagrams=diagrams, next_id=next_id,
                            attachments_rel=attachments_rel, base_url=base_url)

    if tag == "table":
        return _render_table(node, diagrams, next_id, attachments_rel, base_url)

    if tag == "br":
        return "\n"

    if tag == "hr":
        return "\n---\n\n"

    if tag == "structured-macro" and etree.QName(node).namespace and "ac" in etree.QName(node).namespace:
        return _render_macro(node, diagrams, next_id, attachments_rel, base_url)

    # ac:* and ri:* fallbacks handled in _inline; if we get here it's an unknown block
    body = _inline(node, diagrams, next_id, attachments_rel, base_url)
    return body


def _inline(node, diagrams, next_id, attachments_rel, base_url) -> str:
    parts: list[str] = []
    if node.text:
        parts.append(node.text)
    for child in node:
        parts.append(_render_inline(child, diagrams, next_id, attachments_rel, base_url))
        if child.tail:
            parts.append(child.tail)
    return "".join(parts)


def _render_inline(node, diagrams, next_id, attachments_rel, base_url) -> str:
    qname = etree.QName(node)
    tag = qname.localname
    ns = qname.namespace or ""

    if "ac" in ns and tag == "structured-macro":
        return _render_macro(node, diagrams, next_id, attachments_rel, base_url)
    if "ac" in ns and tag == "image":
        return _render_image(node, attachments_rel)
    if "ac" in ns and tag == "link":
        return _render_link(node, base_url, diagrams, next_id, attachments_rel)
    if tag in {"strong", "b"}:
        return f"**{_inline(node, diagrams, next_id, attachments_rel, base_url)}**"
    if tag in {"em", "i"}:
        return f"*{_inline(node, diagrams, next_id, attachments_rel, base_url)}*"
    if tag == "code":
        return f"`{_inline(node, diagrams, next_id, attachments_rel, base_url)}`"
    if tag == "a":
        href = node.get("href", "")
        body = _inline(node, diagrams, next_id, attachments_rel, base_url)
        return f"[{body}]({href})"
    if tag == "br":
        return "\n"
    return _inline(node, diagrams, next_id, attachments_rel, base_url)


def _render_macro(node, diagrams, next_id, attachments_rel, base_url) -> str:
    name = node.get("{http://example.org/ac}name") or ""
    if name in DRAWIO_MACROS:
        diag_id = next_id()
        diagrams[diag_id] = {
            "type": name,
            "xml": etree.tostring(node, encoding="unicode"),
        }
        return f"\n<!-- diagram:{diag_id} -->\n\n"
    if name in ADMONITION_MACROS:
        label = ADMONITION_MACROS[name]
        body_node = node.find("{http://example.org/ac}rich-text-body")
        body = _inline(body_node, diagrams, next_id, attachments_rel, base_url) if body_node is not None else ""
        return f"\n> **{label}:** {body.strip()}\n\n"
    if name == "code":
        lang_param = node.find('{http://example.org/ac}parameter[@{http://example.org/ac}name="language"]')
        lang = (lang_param.text or "") if lang_param is not None else ""
        body_node = node.find("{http://example.org/ac}plain-text-body")
        body = body_node.text or "" if body_node is not None else ""
        return f"\n```{lang}\n{body}\n```\n\n"
    if name == "expand":
        title_param = node.find('{http://example.org/ac}parameter[@{http://example.org/ac}name="title"]')
        title = (title_param.text or "") if title_param is not None else "Details"
        body_node = node.find("{http://example.org/ac}rich-text-body")
        body = _inline(body_node, diagrams, next_id, attachments_rel, base_url) if body_node is not None else ""
        return f"\n**{title}**\n\n{body.strip()}\n\n"
    return f"<!-- macro:{name} -->"


def _render_image(node, attachments_rel) -> str:
    attachment = node.find("{http://example.org/ri}attachment")
    if attachment is not None and attachments_rel:
        filename = attachment.get("{http://example.org/ri}filename", "")
        alt = node.get("{http://example.org/ac}alt") or ""
        return f"![{alt}]({attachments_rel}/{filename})"
    return "<!-- image:unsupported -->"


def _render_link(node, base_url, diagrams, next_id, attachments_rel) -> str:
    page = node.find("{http://example.org/ri}page")
    body_node = node.find("{http://example.org/ac}plain-text-link-body")
    if body_node is None:
        body_node = node.find("{http://example.org/ac}link-body")
    body = (body_node.text or "") if body_node is not None else ""
    if page is not None:
        title = page.get("{http://example.org/ri}content-title", "")
        body = body or title
        return f"[{body}](wiki://page/{title})"
    user = node.find("{http://example.org/ri}user")
    if user is not None:
        return f"@{user.get('{http://example.org/ri}userkey', '')}"
    return body


def _render_list(node, *, ordered, depth, diagrams, next_id, attachments_rel, base_url) -> str:
    out = []
    for i, li in enumerate(node.findall("li"), start=1):
        bullet = f"{i}." if ordered else "-"
        body = _inline(li, diagrams, next_id, attachments_rel, base_url).strip()
        out.append(f"{'  ' * depth}{bullet} {body}")
        for sub in li:
            sub_tag = etree.QName(sub).localname
            if sub_tag in {"ul", "ol"}:
                out.append(_render_list(sub, ordered=(sub_tag == "ol"),
                                        depth=depth + 1, diagrams=diagrams,
                                        next_id=next_id, attachments_rel=attachments_rel,
                                        base_url=base_url).rstrip("\n"))
    return "\n".join(out) + "\n\n"


def _render_table(node, diagrams, next_id, attachments_rel, base_url) -> str:
    rows = node.findall(".//tr")
    if not rows:
        return ""
    out = []
    for i, row in enumerate(rows):
        cells = row.findall("th") + row.findall("td")
        cell_texts = [
            _inline(c, diagrams, next_id, attachments_rel, base_url).replace("\n", " ").strip() or " "
            for c in cells
        ]
        out.append("| " + " | ".join(cell_texts) + " |")
        if i == 0:
            out.append("| " + " | ".join(["---"] * len(cells)) + " |")
    return "\n" + "\n".join(out) + "\n\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--out-md", required=True)
    parser.add_argument("--out-diagrams")
    parser.add_argument("--attachments-rel")
    parser.add_argument("--base-url")
    args = parser.parse_args(argv)

    xhtml = load_xhtml(args.input)
    md, diagrams = convert(xhtml, attachments_rel=args.attachments_rel, base_url=args.base_url)
    Path(args.out_md).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out_md).write_text(md, encoding="utf-8")
    if diagrams and args.out_diagrams:
        Path(args.out_diagrams).write_text(json.dumps(diagrams, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash skills/confluence/tests/test_xhtml_to_md.sh`
Expected: 6 OK lines, "All xhtml_to_md tests passed."

- [ ] **Step 5: Commit**

```bash
git add skills/confluence/lib/xhtml_to_md.py skills/confluence/tests/test_xhtml_to_md.sh
git commit -m "feat(confluence): xhtml_to_md lossy converter with diagram sidecar"
```

---

## Task 3: `md_to_xhtml.py` — markdown → storage format

**Files:**
- Create: `skills/confluence/lib/md_to_xhtml.py`
- Create: `skills/confluence/tests/test_md_to_xhtml.sh`

Reverse direction. Flattens markdown back into Confluence storage XHTML. Diagram placeholders `<!-- diagram:dN -->` re-splice from the sidecar JSON.

- [ ] **Step 1: Write the failing test**

```bash
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
```

```bash
chmod +x skills/confluence/tests/test_md_to_xhtml.sh
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash skills/confluence/tests/test_md_to_xhtml.sh`
Expected: FAIL test 1 (file not found).

- [ ] **Step 3: Implement `md_to_xhtml.py`**

```python
#!/usr/bin/env python3
"""md_to_xhtml.py — convert local markdown back to Confluence storage XHTML.

Recognises:
  - Standard markdown (headings, lists, tables, bold/italic, links, code fences,
    inline code, blockquote, hr, paragraphs)
  - Frontmatter (YAML between leading '---' lines) — stripped from output
  - Image links to ./<path>/<filename> become <ac:image><ri:attachment>
  - <!-- diagram:dN --> placeholders splice from --diagrams-file
  - Blockquotes prefixed with **Info:** / **Warning:** / **Note:** / **Tip:**
    become the matching ac:structured-macro
  - Code fences with a language become ac:name="code" with ac:parameter language

Wiki:// links are passed through verbatim — link_rewrite.py is expected to
have rewritten them to real /pages/<id>/ URLs before this runs in production.
Tests exercise the unresolved case to confirm pass-through.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import xml.sax.saxutils as sax
from pathlib import Path

ADMONITION_PREFIXES = {
    "Info": "info",
    "Warning": "warning",
    "Note": "note",
    "Tip": "tip",
}


def strip_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    fm_block = text[4:end]
    body = text[end + 5 :]
    fm: dict = {}
    for line in fm_block.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            fm[k.strip()] = v.strip().strip('"')
    return fm, body


def parse_blocks(md: str) -> list[tuple[str, str]]:
    """Return list of (kind, body) blocks. kind in {p, h, ul, ol, table, code,
    diagram, hr, blockquote}."""
    blocks: list[tuple[str, str]] = []
    lines = md.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith("#"):
            blocks.append(("h", line))
            i += 1
            continue
        if line.startswith("```"):
            lang = line[3:].strip()
            j = i + 1
            buf = []
            while j < len(lines) and not lines[j].startswith("```"):
                buf.append(lines[j])
                j += 1
            blocks.append(("code", json.dumps({"lang": lang, "body": "\n".join(buf)})))
            i = j + 1
            continue
        if re.match(r"^<!-- diagram:(d\d+) -->\s*$", line):
            blocks.append(("diagram", re.match(r"^<!-- diagram:(d\d+) -->", line).group(1)))
            i += 1
            continue
        if line.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s\-|]+\|\s*$", lines[i + 1]):
            buf = [line]
            j = i + 1
            while j < len(lines) and lines[j].lstrip().startswith("|"):
                buf.append(lines[j])
                j += 1
            blocks.append(("table", "\n".join(buf)))
            i = j
            continue
        if line.startswith("- ") or line.startswith("* "):
            buf = []
            while i < len(lines) and (lines[i].startswith("- ") or lines[i].startswith("* ") or lines[i].startswith("  ")):
                buf.append(lines[i])
                i += 1
            blocks.append(("ul", "\n".join(buf)))
            continue
        if re.match(r"^\d+\. ", line):
            buf = []
            while i < len(lines) and (re.match(r"^\d+\. ", lines[i]) or lines[i].startswith("  ")):
                buf.append(lines[i])
                i += 1
            blocks.append(("ol", "\n".join(buf)))
            continue
        if line.startswith(">"):
            buf = []
            while i < len(lines) and (lines[i].startswith(">") or lines[i].strip() == ""):
                if lines[i].startswith(">"):
                    buf.append(lines[i][1:].lstrip())
                i += 1
                if i < len(lines) and not lines[i].startswith(">"):
                    break
            blocks.append(("blockquote", "\n".join(buf)))
            continue
        if line.strip() == "---":
            blocks.append(("hr", ""))
            i += 1
            continue
        # paragraph
        buf = [line]
        i += 1
        while i < len(lines) and lines[i].strip() and not lines[i].startswith(("#", "```", "|", "- ", "* ", ">")):
            buf.append(lines[i])
            i += 1
        blocks.append(("p", " ".join(buf)))
    return blocks


def render_inline(text: str) -> str:
    out = sax.escape(text)
    # &lt;...&gt; got escaped; keep simple: bold, italic, code, image, link
    # We re-process using regexes against the unescaped text first to avoid double-escape, simpler:
    raw = text
    # images
    raw = re.sub(r"!\[([^\]]*)\]\(\./([^)]+)\)",
                 lambda m: _image_xml(m.group(1), m.group(2)), raw)
    # links
    raw = re.sub(r"\[([^\]]+)\]\(([^)]+)\)",
                 lambda m: f'<a href="{sax.escape(m.group(2), {chr(34): "&quot;"})}">{sax.escape(m.group(1))}</a>',
                 raw)
    # bold
    raw = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", raw)
    # italic
    raw = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", raw)
    # code
    raw = re.sub(r"`([^`]+)`", lambda m: f"<code>{sax.escape(m.group(1))}</code>", raw)
    return raw


def _image_xml(alt: str, rel_path: str) -> str:
    filename = rel_path.rsplit("/", 1)[-1]
    alt_attr = f' ac:alt="{sax.escape(alt, {chr(34): "&quot;"})}"' if alt else ""
    return f'<ac:image{alt_attr}><ri:attachment ri:filename="{sax.escape(filename, {chr(34): "&quot;"})}"/></ac:image>'


def render_block(kind: str, body: str, diagrams: dict) -> str:
    if kind == "h":
        m = re.match(r"^(#+)\s+(.*)$", body)
        level = len(m.group(1))
        return f"<h{level}>{render_inline(m.group(2))}</h{level}>"
    if kind == "p":
        # admonition shorthand: paragraph that's actually a blockquote? handled in blockquote branch
        return f"<p>{render_inline(body)}</p>"
    if kind == "ul":
        items = [render_inline(line[2:].strip()) for line in body.splitlines() if line.startswith(("- ", "* "))]
        return "<ul>" + "".join(f"<li>{it}</li>" for it in items) + "</ul>"
    if kind == "ol":
        items = [render_inline(re.sub(r"^\d+\.\s+", "", line)) for line in body.splitlines() if re.match(r"^\d+\. ", line)]
        return "<ol>" + "".join(f"<li>{it}</li>" for it in items) + "</ol>"
    if kind == "code":
        meta = json.loads(body)
        lang = meta["lang"]
        text = sax.escape(meta["body"])
        lang_param = f'<ac:parameter ac:name="language">{sax.escape(lang)}</ac:parameter>' if lang else ""
        return (
            f'<ac:structured-macro ac:name="code">'
            f"{lang_param}"
            f"<ac:plain-text-body><![CDATA[{meta['body']}]]></ac:plain-text-body>"
            f"</ac:structured-macro>"
        )
    if kind == "diagram":
        diag_id = body
        if diag_id in diagrams:
            return diagrams[diag_id]["xml"]
        return f"<!-- missing diagram: {diag_id} -->"
    if kind == "blockquote":
        for prefix, macro in ADMONITION_PREFIXES.items():
            head = f"**{prefix}:**"
            if body.lstrip().startswith(head):
                inner = body.lstrip()[len(head):].lstrip()
                return (
                    f'<ac:structured-macro ac:name="{macro}">'
                    f"<ac:rich-text-body><p>{render_inline(inner)}</p></ac:rich-text-body>"
                    f"</ac:structured-macro>"
                )
        return f"<blockquote><p>{render_inline(body)}</p></blockquote>"
    if kind == "table":
        rows = [r for r in body.splitlines() if r.strip().startswith("|")]
        if not rows:
            return ""
        head = [c.strip() for c in rows[0].strip().strip("|").split("|")]
        out = ["<table>"]
        out.append("<tr>" + "".join(f"<th>{render_inline(c)}</th>" for c in head) + "</tr>")
        for r in rows[2:]:
            cells = [c.strip() for c in r.strip().strip("|").split("|")]
            out.append("<tr>" + "".join(f"<td>{render_inline(c)}</td>" for c in cells) + "</tr>")
        out.append("</table>")
        return "".join(out)
    if kind == "hr":
        return "<hr/>"
    return ""


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--md-file", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--diagrams-file")
    args = parser.parse_args(argv)

    text = Path(args.md_file).read_text(encoding="utf-8")
    _, body = strip_frontmatter(text)

    diagrams: dict = {}
    if args.diagrams_file and Path(args.diagrams_file).is_file():
        diagrams = json.loads(Path(args.diagrams_file).read_text())

    blocks = parse_blocks(body)
    out = "".join(render_block(k, b, diagrams) for k, b in blocks)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(out, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash skills/confluence/tests/test_md_to_xhtml.sh`
Expected: 6 OK lines.

- [ ] **Step 5: Commit**

```bash
git add skills/confluence/lib/md_to_xhtml.py skills/confluence/tests/test_md_to_xhtml.sh
git commit -m "feat(confluence): md_to_xhtml encoder with diagram splicing"
```

---

## Task 4: `link_rewrite.py` — intra-tree link resolution

**Files:**
- Create: `skills/confluence/lib/link_rewrite.py`
- Create: `skills/confluence/tests/test_link_rewrite.sh`

Two operating modes:

1. **Build map**: walk a local tree, parse frontmatter from every .md, return `{source_page_id, source_title} → relative_path`.
2. **Rewrite**: read a single .md, replace `wiki://page/<title>` links with relative paths to peers in the tree if the title matches; leave un-matched links as `wiki://page/...` for `tree_upload.py` to convert to real URLs once destination IDs are known.

- [ ] **Step 1: Write the failing test**

```bash
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

echo ""
echo "All link_rewrite tests passed."
```

```bash
chmod +x skills/confluence/tests/test_link_rewrite.sh
```

- [ ] **Step 2: Run to verify failure**

Run: `bash skills/confluence/tests/test_link_rewrite.sh`
Expected: FAIL on test 1.

- [ ] **Step 3: Implement `link_rewrite.py`**

```python
#!/usr/bin/env python3
"""link_rewrite.py — manage cross-page links inside a local tree.

Subcommands:

  build-map --tree <dir> --out <map.json>
      Walk every .md under <dir>, parse YAML frontmatter, write:
        { "<source_page_id>": { "title": "<source_title>",
                                "relative_path": "<path/from/tree/root.md>",
                                "abs_path": "<absolute/path.md>" } }

  rewrite --md-file <file> --map <map.json>
      In-place: replace wiki://page/<title> links whose <title> matches
      a known title in the map with a relative path to that peer.
      Unknown titles are left untouched (tree_upload.py turns them into
      real Confluence URLs after pages are created).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path


WIKI_LINK_RE = re.compile(r"\[([^\]]+)\]\(wiki://page/([^)]+)\)")


def parse_frontmatter(text: str) -> dict:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}
    fm: dict = {}
    for line in text[4:end].splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            fm[k.strip()] = v.strip().strip('"')
    return fm


def cmd_build_map(args: argparse.Namespace) -> int:
    tree = Path(args.tree).resolve()
    result: dict = {}
    for md in tree.rglob("*.md"):
        text = md.read_text(encoding="utf-8")
        fm = parse_frontmatter(text)
        page_id = fm.get("source_page_id")
        if not page_id:
            continue
        result[page_id] = {
            "title": fm.get("source_title", ""),
            "relative_path": str(md.relative_to(tree)),
            "abs_path": str(md),
        }
    Path(args.out).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    return 0


def cmd_rewrite(args: argparse.Namespace) -> int:
    md_path = Path(args.md_file).resolve()
    map_data: dict = json.loads(Path(args.map).read_text())
    title_to_path = {v["title"]: v["abs_path"] for v in map_data.values() if v.get("title")}

    text = md_path.read_text(encoding="utf-8")

    def repl(m: re.Match) -> str:
        label, title = m.group(1), m.group(2)
        target_abs = title_to_path.get(title)
        if not target_abs:
            return m.group(0)
        rel = os.path.relpath(target_abs, md_path.parent)
        if not rel.startswith("."):
            rel = f"./{rel}"
        return f"[{label}]({rel})"

    new_text = WIKI_LINK_RE.sub(repl, text)
    md_path.write_text(new_text, encoding="utf-8")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_build = sub.add_parser("build-map")
    p_build.add_argument("--tree", required=True)
    p_build.add_argument("--out", required=True)
    p_build.set_defaults(func=cmd_build_map)

    p_rw = sub.add_parser("rewrite")
    p_rw.add_argument("--md-file", required=True)
    p_rw.add_argument("--map", required=True)
    p_rw.set_defaults(func=cmd_rewrite)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run to verify pass**

Run: `bash skills/confluence/tests/test_link_rewrite.sh`
Expected: 2 OK lines.

- [ ] **Step 5: Commit**

```bash
git add skills/confluence/lib/link_rewrite.py skills/confluence/tests/test_link_rewrite.sh
git commit -m "feat(confluence): link_rewrite for intra-tree page links"
```

---

## Task 5: `tree_fetch.py` — recursive descendant walk + attachment download

**Files:**
- Create: `skills/confluence/lib/tree_fetch.py`
- Create: `skills/confluence/tests/test_tree_fetch.sh`

Walks `/rest/api/content/{rootId}/child/page` recursively (paginated), saves a markdown tree with frontmatter, downloads each page's attachments to a sibling directory. Writes `manifest.json` at the tree root summarizing what was fetched.

- [ ] **Step 1: Write the failing test using a mock REST server**

Same pattern as existing `test_push_conflict.sh` — Python `http.server` thread that responds to:
- `GET /rest/api/content/100` → fake root page
- `GET /rest/api/content/100/child/page` → list of children `[{"id": "200", "title": "Child"}]`
- `GET /rest/api/content/200` → fake child page
- `GET /rest/api/content/200/child/page` → empty list
- `GET /rest/api/content/{id}/child/attachment` → empty list (test attachments separately)
- `GET /download/...` → 200 OK with bytes

Assert:
- `_root.md` exists with frontmatter `source_page_id: "100"`
- `child-<slug>/_index.md` exists with frontmatter `source_page_id: "200"`
- `manifest.json` lists both pages with relative paths

(Full bash test ~80 lines; structure mirrors `test_push_conflict.sh` from the existing skill scaffold. The existing test's `cat > $TMP/server.py <<PYEOF ... PYEOF` pattern is the template. Do not omit any test code in the actual plan execution — write the full server stub and assertions.)

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement `tree_fetch.py`**

Key responsibilities:
1. `auth_header(user, secret)` and `base_url(host)` — copy from `push.py` (or import). The plan in execution writes a tiny `_http.py` shared helper in `lib/` if both push and fetch end up needing them. For now, duplicate (DRY win is small here).
2. `fetch_page(host, page_id, auth)` — GET with `?expand=body.storage,version,space,ancestors,children.attachment`.
3. `fetch_children_recursive(host, root_id, auth)` — yield (page_id, parent_id, depth) tuples in pre-order. Paginate `/child/page?start=N&limit=25`.
4. For each page:
   - slugify title (lowercased, non-alphanumeric → hyphens, max 40 chars)
   - root → `_root.md`; non-root → `<slug>/_index.md` (path is parent's directory + new subdir)
   - call `xhtml_to_md.convert` programmatically (import the function rather than shelling out)
   - Write frontmatter block then markdown body
   - For each attachment: download to `<page-dir>/<filename-of-md>.attachments/`
5. Write `manifest.json` at the tree root with `{ "root_id", "root_title", "fetched_at", "pages": [...] }`.

- [ ] **Step 4: Run to verify pass**

- [ ] **Step 5: Commit**

```bash
git add skills/confluence/lib/tree_fetch.py skills/confluence/tests/test_tree_fetch.sh
git commit -m "feat(confluence): tree_fetch recursive descendant walker"
```

---

## Task 6: Refactor `push.py` and `attach.py`

**Files:**
- Modify: `skills/confluence/lib/push.py`
- Modify: `skills/confluence/lib/attach.py`
- Rename: `skills/confluence/tests/test_push_conflict.sh` → `test_push.sh`
- Modify: `skills/confluence/tests/test_attach.sh`

- [ ] **Step 1: Strip update path from `push.py`**

The `update()` function and the version-conflict abort path are unused in the migration flow (we always create new pages). Two options:
1. Remove `update()` entirely — clean; deletes ~50 lines.
2. Keep but mark as future use — unused code is debt.

Take option 1. Keep `create()` and `auth_header` and `base_url` and `http_json`. Drop `update()`, drop the `--meta-file` argument, drop the version-conflict logic.

After change, `push.py` exports just `create()` plus a CLI that invokes it.

Update `tests/test_push_conflict.sh`:
- Rename file: `git mv tests/test_push_conflict.sh tests/test_push.sh`
- Drop tests 1 and 2 (happy update + conflict)
- Keep test 3 (PAT auto-detect) but rewrite to exercise `create` instead of update
- Add a new test 1: happy create, response includes new page id, prints id to stdout
- Add a new test 2: 401 returns exit code 3

- [ ] **Step 2: Adapt `attach.py` to emit `<ac:image>` reference, not `[ri:imgN]`**

Today `attach.py` uploads then rewrites `![alt](./local.png)` → `![alt][ri:img1]`. In the migration flow the markdown is *already* `![alt](./_index.attachments/diagram.png)` (set by `xhtml_to_md`), and `md_to_xhtml` converts that to `<ac:image>` directly. So `attach.py` no longer rewrites the markdown — it just uploads the file.

Change:
1. Rename `LOCAL_IMG_RE` to scan markdown for `![alt](./<path>/<filename>)` references where the path resolves to an existing file.
2. For each, POST attachment.
3. Skip the markdown rewrite step entirely.
4. Remove the `meta.json` write — there is no meta.json in this design.

CLI signature changes:
```
python3 attach.py --md-file <file> --page-id <id> --host <host> --user <user>
```
Returns 0 if all uploads succeeded.

Update `tests/test_attach.sh`:
- Drop tests 1 (anchor rewrite) and 5 (meta.anchors populated)
- Keep tests 2, 3, 4 (http URL skip, missing file warn, multipart correctness)
- Add new test: page-id flag is in the upload URL

- [ ] **Step 3: Run both updated test suites**

Run: `bash skills/confluence/tests/test_push.sh`
Run: `bash skills/confluence/tests/test_attach.sh`
Expected: All OK.

- [ ] **Step 4: Commit**

```bash
git add skills/confluence/lib/push.py skills/confluence/lib/attach.py
git rm skills/confluence/tests/test_push_conflict.sh
git add skills/confluence/tests/test_push.sh skills/confluence/tests/test_attach.sh
git commit -m "refactor(confluence): trim push to create-only, drop attach anchor rewrite"
```

---

## Task 7: `tree_upload.py` — two-pass uploader

**Files:**
- Create: `skills/confluence/lib/tree_upload.py`
- Create: `skills/confluence/tests/test_tree_upload.sh`

Walks the local tree, builds the link map, then:
1. **Stub pass:** create every page with a placeholder body (single paragraph "migrated, content pending"). Records `source_page_id → new_page_id`.
2. **Content pass:** for each page, run `link_rewrite` against a copy of the md (so the original on disk stays in `wiki://` form), then `attach.py` for images, then `md_to_xhtml.py`, then PUT the storage XHTML to the new page (this *is* the update path on a stub we just created — version is always 1, no conflict possible).

- [ ] **Step 1: Write test using mock REST server with full create+update support**

Follow the same mock server pattern. Add response handlers for POST `/rest/api/content` (returns new page with id) and PUT `/rest/api/content/{id}` (returns echo).

Test scenarios:
1. Tree with 2 pages, both stub-created and content-updated
2. Wiki-link inside the tree gets rewritten to `/pages/<new-id>/<title>` URL after both stubs exist
3. If stub pass fails midway, no content pass runs, error message lists what was created

- [ ] **Step 2: Run failing**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run passing**
- [ ] **Step 5: Commit**

```bash
git add skills/confluence/lib/tree_upload.py skills/confluence/tests/test_tree_upload.sh
git commit -m "feat(confluence): tree_upload two-pass uploader"
```

---

## Task 8: Update SKILL.md workflows to invoke the new libs

**Files:**
- Modify: `skills/confluence/SKILL.md` (already drafted in Task 1 — fill in the workflow sections with concrete bash now)

- [ ] **Step 1: Fill in `## Workflow: tree-fetch`**

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
[[ -z "${CONFLUENCE_HOST:-}" ]] && { echo "ERROR: CONFLUENCE_HOST not in config.sh — run: bash scripts/credentials/service.sh confluence add" >&2; exit 1; }

PAGE_ID="$1"
SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
_PASS=$(require_secret "$SLUG" "$CONFLUENCE_USER") || exit 1

CONFLUENCE_PASS="$_PASS" python3 "$SKILL_DIR/lib/tree_fetch.py" \
  --host "$CONFLUENCE_HOST" \
  --user "$CONFLUENCE_USER" \
  --root-id "$PAGE_ID" \
  --out-dir "./docs/confluence-trees/$(date +%Y-%m-%d)-${PAGE_ID}"
unset _PASS
```

- [ ] **Step 2: Fill in `## Workflow: tree-upload`**

```bash
LOCAL_DIR="$1"
NEW_PARENT="$2"
SPACE_KEY="$3"

source ~/.agent-skills-setup/lib.sh
load_config || exit 1
SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
_PASS=$(require_secret "$SLUG" "$CONFLUENCE_USER") || exit 1

# Build the source_page_id → relative_path map
python3 "$SKILL_DIR/lib/link_rewrite.py" build-map \
  --tree "$LOCAL_DIR" \
  --out "$LOCAL_DIR/.link-map.json"

CONFLUENCE_PASS="$_PASS" python3 "$SKILL_DIR/lib/tree_upload.py" \
  --tree "$LOCAL_DIR" \
  --link-map "$LOCAL_DIR/.link-map.json" \
  --new-parent "$NEW_PARENT" \
  --space "$SPACE_KEY" \
  --host "$CONFLUENCE_HOST" \
  --user "$CONFLUENCE_USER"

unset _PASS
rm -f "$LOCAL_DIR/.link-map.json"
```

- [ ] **Step 3: Fill in `## Workflow: link-rewrite-preview`**

Dry run that prints what would change without modifying files. `tree_upload.py --dry-run` flag.

- [ ] **Step 4: Commit**

```bash
git add skills/confluence/SKILL.md
git commit -m "docs(confluence): SKILL.md concrete workflows for migration"
```

---

## Task 9: Install verification + integration check

**Files:** none modified, verification only.

- [ ] **Step 1: Reinstall**

```bash
cd ~/Project/agent-skills-setup
bash scripts/install.sh --agent claude
```

Confirm `~/.claude/skills/confluence/` symlink resolves to the repo and contains `lib/xhtml_to_md.py`, `lib/md_to_xhtml.py`, `lib/tree_fetch.py`, `lib/tree_upload.py`, `lib/link_rewrite.py`, `lib/push.py`, `lib/attach.py`. No `storage_codec.py`, no `_index.meta.json` references.

- [ ] **Step 2: Run all confluence tests**

```bash
for t in skills/confluence/tests/test_*.sh; do
  echo "=== $t ==="
  bash "$t" || exit 1
done
```

Expected: all pass.

- [ ] **Step 3: Verify `fetch-jira-story` flow is unaffected**

Read `skills/fetch-jira-story/SKILL.md`. Confirm it still calls the old `fetch-page-to-markdown` flow (curl + `html2md.py`) and does NOT depend on the deleted `storage_codec.py` or any new confluence-skill library.

If by any chance a previous edit wired jira-story into the now-deleted codec, restore the original behavior.

- [ ] **Step 4: Smoke test fetch against a real instance**

Manual: `cd ~/some-test-repo` and run `/confluence-tree-fetch <small-page-id>`. Confirm the local tree shape matches expectations and no errors.

If that succeeds, also test `/confluence-tree-upload <local-dir> --parent <new-parent-id> --space <KEY>` against a sandbox space. Verify the new pages exist, links resolve correctly between them.

- [ ] **Step 5: Commit nothing if smoke passes; if it surfaces a bug, fix and commit**

---

## Done criteria

- [ ] Plan-described file structure exists; old codec/round-trip files deleted
- [ ] All five task-specific shell test suites pass
- [ ] Install creates working symlinks under `~/.claude/skills/confluence/`
- [ ] Real-instance smoke test of fetch + upload completes without errors
- [ ] `fetch-jira-story` continues to function unchanged
- [ ] README, SKILL.md, charter all describe the migration flow consistently — no references to round-trip, `.meta.json`, or version-conflict abort

---

## Risks and known limitations

1. **Lossy converter is the new reality.** Anything that's not in the recognised macro list comes through as `<!-- macro:<name> -->`. Users who lean on Confluence-specific macros will see content holes. Real fixtures from your instance will surface which macros to add to the recognized list before this skill is "done."

2. **Wiki:// link resolution depends on title uniqueness.** Confluence allows duplicate page titles in different spaces. The current map is keyed by title; collisions silently rewrite to the first match. If your source tree has duplicate-title pages, links break in non-obvious ways. **Mitigation:** add a warning during `build-map` when two pages share a title.

3. **Stub pass can leave orphans on partial failure.** If 50 of 100 stubs are created and the 51st fails, the 50 created pages exist on the destination wiki under the new parent. The skill prints what was created so the user can clean up manually. No automatic rollback (would require destructive deletes — too risky for a migration tool).

4. **No support for restricted pages.** If the API user lacks read on a descendant, `fetch_children_recursive` skips it silently (Confluence returns the page as missing rather than 403 in some configurations). The skill should at minimum log the count of skipped pages — add this to `tree_fetch.py`.

5. **Attachment 100MB limit unchanged from prior plan.** Larger files fail fast.

6. **Cross-tree links to outside pages stay as `wiki://page/<title>` URLs.** The user can manually fix these in markdown before upload, or accept that unresolved wiki:// links pass through verbatim and end up as broken anchors on the destination page. **Mitigation:** `--strict` flag on tree_upload that aborts if any unresolved wiki:// links remain. Default is permissive.

## Out of scope (for this plan)

- Atlassian Cloud (different API, ADF format)
- Round-trip editing of existing pages (use the destination Confluence editor)
- Drawio/Gliffy XML editing (open in Confluence to edit)
- Page move / delete / permissions
- Incremental sync (always full re-fetch and full re-upload)
- Concurrent uploads (sequential is simpler; tree sizes are bounded)

## What's still needed before this can ship

Real XHTML fixtures from your Confluence instance. List in `tests/fixtures/README.md`:
- One simple text+heading+list page
- One with a code macro (with language)
- One with an info macro
- One with an image attachment
- One with drawio (to confirm the exact `ac:name` your plugin uses)
- One page that links to another page in the same tree

Without these, the converter is guessing. The unit tests in this plan use synthesized XHTML which catches structural bugs but won't catch instance-specific quirks.
