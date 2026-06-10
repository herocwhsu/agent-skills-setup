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


_DIAGRAM_LINE_RE = re.compile(r"^<!-- diagram:d\d+ -->\s*$")


def _starts_block(line: str) -> bool:
    if not line:
        return False
    if line.startswith(("#", "```", "|", "- ", "* ", ">")):
        return True
    if re.match(r"^\d+\.\s", line):
        return True
    if line.strip() == "---":
        return True
    if _DIAGRAM_LINE_RE.match(line):
        return True
    return False


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
        while i < len(lines) and lines[i].strip() and not _starts_block(lines[i]):
            buf.append(lines[i])
            i += 1
        blocks.append(("p", " ".join(buf)))
    return blocks


def render_inline(text: str) -> str:
    # Escape XML-significant chars in the raw text first. Subsequent regex
    # substitutions emit XHTML tags whose `<` and `>` must remain literal.
    raw = sax.escape(text)
    # images (must come before links — `![...](url)` would otherwise match the link regex)
    raw = re.sub(r"!\[([^\]]*)\]\(\./([^)]+)\)",
                 lambda m: _image_xml(m.group(1), m.group(2)), raw)
    # links
    raw = re.sub(r"\[([^\]]+)\]\(([^)]+)\)",
                 lambda m: f'<a href="{m.group(2).replace(chr(34), "&quot;")}">{m.group(1)}</a>',
                 raw)
    # bold (must come before italic so `**x**` is not parsed as `*<em>x</em>*`)
    raw = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", raw)
    # italic
    raw = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", raw)
    # inline code
    raw = re.sub(r"`([^`]+)`", lambda m: f"<code>{m.group(1)}</code>", raw)
    return raw


def _image_xml(alt: str, rel_path: str) -> str:
    filename = rel_path.rsplit("/", 1)[-1]
    alt_attr = f' ac:alt="{alt.replace(chr(34), "&quot;")}"' if alt else ""
    return f'<ac:image{alt_attr}><ri:attachment ri:filename="{filename.replace(chr(34), "&quot;")}"/></ac:image>'


def render_block(kind: str, body: str, diagrams: dict) -> str:
    if kind == "h":
        m = re.match(r"^(#+)\s+(.*)$", body)
        if not m:
            return f"<p>{render_inline(body)}</p>"
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
