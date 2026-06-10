#!/usr/bin/env python3
"""xhtml_to_md.py — convert Confluence storage XHTML to readable markdown.

Lossy by design. Macros flatten:
    info/warning/note      → blockquote with bold prefix
    code (with language)   → fenced code block
    expand                 → bold title + body
    drawio / drawio-board  → placeholder <!-- diagram:dN --> + sidecar JSON
    gliffy                 → same as drawio
    other ac:* macros      → silently dropped (no placeholder, no sidecar)
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
import html.entities
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote

try:
    from lxml import etree
except ImportError:
    print("ERROR: lxml required. Install with: pip3 install lxml", file=sys.stderr)
    sys.exit(2)

NS = {
    "ac": "http://example.org/ac",  # Confluence storage uses bare ac:, ri: — we add these via wrapping
    "ri": "http://example.org/ri",
}

# Confluence storage XHTML may declare its own ac:/ri: URIs on the fragment.
# Recognise the synthetic ones we wrap with plus the real Confluence ones.
_REAL_NS = {
    "ac": {"http://example.org/ac", "http://atlassian.com/content"},
    "ri": {"http://example.org/ri", "http://atlassian.com/resource/identifier"},
}

DRAWIO_MACROS = {"drawio", "drawio-board", "drawio-mxgraph", "gliffy"}
ADMONITION_MACROS = {"info": "Info", "warning": "Warning", "note": "Note", "tip": "Tip"}

_ENTITY_RE = re.compile(r"&([A-Za-z][A-Za-z0-9]+);")
# These must stay literal so lxml's XML parser doesn't choke.
_XML_RESERVED_ENTITIES = {"amp", "lt", "gt", "quot", "apos"}


def _substitute_entities(text: str) -> str:
    """Decode XHTML named entities (e.g. &nbsp;, &copy;) before XML parsing.

    Leaves the five XML-significant entities alone so lxml stays happy.
    """

    def repl(m: re.Match) -> str:
        name = m.group(1)
        if name in _XML_RESERVED_ENTITIES:
            return m.group(0)
        codepoint = html.entities.html5.get(name + ";") or html.entities.html5.get(name)
        return codepoint if codepoint else m.group(0)

    return _ENTITY_RE.sub(repl, text)


def wrap_with_ns(xhtml: str) -> str:
    """Wrap a fragment with explicit namespace declarations so lxml can parse it."""
    xhtml = _substitute_entities(xhtml)
    return (
        '<root xmlns:ac="http://example.org/ac" xmlns:ri="http://example.org/ri">'
        f"{xhtml}"
        "</root>"
    )


def _ns_matches(node, prefix: str) -> bool:
    """True if `node` belongs to a namespace effectively bound to `prefix` (ac/ri).

    Matches both the synthetic URIs we wrap with and the real Confluence URIs.
    Falls back to substring match so an unexpected variant URI still resolves.
    """
    ns = etree.QName(node).namespace or ""
    if ns in _REAL_NS.get(prefix, set()):
        return True
    return prefix in ns.lower()


def _attr(node, prefix: str, local: str):
    """Return attribute value matching `<prefix>:<local>` regardless of bound URI."""
    for full_name, value in node.attrib.items():
        qname = etree.QName(full_name)
        if qname.localname != local:
            continue
        ns = (qname.namespace or "").lower()
        if not ns:
            # Unprefixed attribute on a prefixed element: treat as matching.
            return value
        if ns in _REAL_NS.get(prefix, set()) or prefix in ns:
            return value
    return None


def _find_child(node, prefix: str, local: str):
    """First direct child with matching local name + prefix-bound namespace."""
    for child in node:
        qname = etree.QName(child)
        if qname.localname == local:
            ns = (qname.namespace or "").lower()
            if ns in _REAL_NS.get(prefix, set()) or prefix in ns:
                return child
    return None


def _find_descendant(node, prefix: str, local: str):
    """First descendant with matching local name + prefix-bound namespace."""
    for child in node.iter():
        if child is node:
            continue
        qname = etree.QName(child)
        if qname.localname == local:
            ns = (qname.namespace or "").lower()
            if ns in _REAL_NS.get(prefix, set()) or prefix in ns:
                return child
    return None


def _find_macro_param(node, name_value: str):
    """Find <ac:parameter ac:name="<name_value>"> child regardless of namespace URI."""
    for child in node:
        qname = etree.QName(child)
        if qname.localname != "parameter":
            continue
        ns = (qname.namespace or "").lower()
        if not (ns in _REAL_NS["ac"] or "ac" in ns):
            continue
        if _attr(child, "ac", "name") == name_value:
            return child
    return None


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

    if tag == "structured-macro" and _ns_matches(node, "ac"):
        return _render_macro(node, diagrams, next_id, attachments_rel, base_url)

    # ac:* and ri:* fallbacks handled in _inline; if we get here it's an unknown block.
    # Append paragraph separator so back-to-back unknown blocks don't fuse.
    body = _inline(node, diagrams, next_id, attachments_rel, base_url)
    return body + ("\n\n" if body.strip() else "")


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

    if tag == "structured-macro" and _ns_matches(node, "ac"):
        return _render_macro(node, diagrams, next_id, attachments_rel, base_url)
    if tag == "image" and _ns_matches(node, "ac"):
        return _render_image(node, attachments_rel)
    if tag == "link" and _ns_matches(node, "ac"):
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
    name = _attr(node, "ac", "name") or ""
    if name in DRAWIO_MACROS:
        diag_id = next_id()
        diagrams[diag_id] = {
            "type": name,
            "xml": etree.tostring(node, encoding="unicode"),
        }
        return f"\n<!-- diagram:{diag_id} -->\n\n"
    if name in ADMONITION_MACROS:
        label = ADMONITION_MACROS[name]
        body_node = _find_child(node, "ac", "rich-text-body")
        body = _inline(body_node, diagrams, next_id, attachments_rel, base_url) if body_node is not None else ""
        return f"\n> **{label}:** {body.strip()}\n\n"
    if name == "code":
        lang_param = _find_macro_param(node, "language")
        lang = (lang_param.text or "") if lang_param is not None else ""
        body_node = _find_child(node, "ac", "plain-text-body")
        body = body_node.text or "" if body_node is not None else ""
        return f"\n```{lang}\n{body}\n```\n\n"
    if name == "expand":
        title_param = _find_macro_param(node, "title")
        title = (title_param.text or "") if title_param is not None else "Details"
        body_node = _find_child(node, "ac", "rich-text-body")
        body = _inline(body_node, diagrams, next_id, attachments_rel, base_url) if body_node is not None else ""
        return f"\n**{title}**\n\n{body.strip()}\n\n"
    return ""


def _render_image(node, attachments_rel) -> str:
    attachment = _find_child(node, "ri", "attachment")
    if attachment is not None and attachments_rel:
        filename = _attr(attachment, "ri", "filename") or ""
        alt = _attr(node, "ac", "alt") or ""
        # Filename goes into the URL part: percent-encode parens/brackets.
        encoded_filename = quote(filename, safe=" /")
        # Alt text is link-body; escape closing/opening brackets.
        safe_alt = alt.replace("]", r"\]").replace("[", r"\[")
        return f"![{safe_alt}]({attachments_rel}/{encoded_filename})"
    return "<!-- image:unsupported -->"


def _render_link(node, base_url, diagrams, next_id, attachments_rel) -> str:
    page = _find_child(node, "ri", "page")
    body_node = _find_child(node, "ac", "plain-text-link-body")
    if body_node is None:
        body_node = _find_child(node, "ac", "link-body")
    body = (body_node.text or "") if body_node is not None else ""
    if page is not None:
        title = _attr(page, "ri", "content-title") or ""
        body = body or title
        # Body sits inside [...]: escape ] so renderers don't end the link early.
        safe_body = body.replace("]", r"\]")
        # Title sits inside (...): percent-encode (), [], and the like.
        encoded_title = quote(title, safe=" ")
        return f"[{safe_body}](wiki://page/{encoded_title})"
    user = _find_child(node, "ri", "user")
    if user is not None:
        return f"@{_attr(user, 'ri', 'userkey') or ''}"
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
