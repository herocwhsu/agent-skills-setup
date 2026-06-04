#!/usr/bin/env python3
"""Convert HTML (from stdin) to Markdown (to stdout).

Usage:
    echo "<html>..." | python3 html2md.py
    cat page.html   | python3 html2md.py
"""
import re
import sys


def html2md(html: str) -> str:
    # Remove script/style blocks entirely
    html = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', html, flags=re.DOTALL | re.IGNORECASE)

    # Headings
    for i in range(1, 7):
        html = re.sub(rf'<h{i}[^>]*>(.*?)</h{i}>', lambda m, n=i: f'\n{"#"*n} {_strip(m.group(1))}\n', html, flags=re.DOTALL | re.IGNORECASE)

    # Bold / italic
    html = re.sub(r'<(strong|b)[^>]*>(.*?)</\1>', lambda m: f'**{_strip(m.group(2))}**', html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r'<(em|i)[^>]*>(.*?)</\1>', lambda m: f'*{_strip(m.group(2))}*', html, flags=re.DOTALL | re.IGNORECASE)

    # Code
    html = re.sub(r'<code[^>]*>(.*?)</code>', lambda m: f'`{_strip(m.group(1))}`', html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r'<pre[^>]*>(.*?)</pre>', lambda m: f'\n```\n{_strip(m.group(1))}\n```\n', html, flags=re.DOTALL | re.IGNORECASE)

    # Links
    html = re.sub(r'<a[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', lambda m: f'[{_strip(m.group(2))}]({m.group(1)})', html, flags=re.DOTALL | re.IGNORECASE)

    # Tables
    html = re.sub(r'<table[^>]*>(.*?)</table>', _convert_table, html, flags=re.DOTALL | re.IGNORECASE)

    # Lists
    html = re.sub(r'<li[^>]*>(.*?)</li>', lambda m: f'- {_strip(m.group(1))}\n', html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r'<[uo]l[^>]*>(.*?)</[uo]l>', r'\1\n', html, flags=re.DOTALL | re.IGNORECASE)

    # Paragraphs and breaks
    html = re.sub(r'<br\s*/?>', '\n', html, flags=re.IGNORECASE)
    html = re.sub(r'<p[^>]*>(.*?)</p>', lambda m: f'{_strip(m.group(1))}\n\n', html, flags=re.DOTALL | re.IGNORECASE)

    # Horizontal rule
    html = re.sub(r'<hr\s*/?>', '\n---\n', html, flags=re.IGNORECASE)

    # Strip remaining tags
    html = re.sub(r'<[^>]+>', '', html)

    # Decode common HTML entities
    entities = {'&amp;': '&', '&lt;': '<', '&gt;': '>', '&nbsp;': ' ',
                '&#39;': "'", '&quot;': '"', '&apos;': "'"}
    for ent, char in entities.items():
        html = html.replace(ent, char)

    # Collapse 3+ blank lines → 2
    html = re.sub(r'\n{3,}', '\n\n', html)
    return html.strip()


def _strip(html: str) -> str:
    """Remove all tags and decode entities from a fragment."""
    text = re.sub(r'<[^>]+>', '', html)
    text = text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>') \
               .replace('&nbsp;', ' ').replace('&#39;', "'").replace('&quot;', '"')
    return text.strip()


def _convert_table(m: re.Match) -> str:
    table_html = m.group(1)
    rows = re.findall(r'<tr[^>]*>(.*?)</tr>', table_html, re.DOTALL | re.IGNORECASE)
    if not rows:
        return ''
    md_rows = []
    for i, row in enumerate(rows):
        cells = re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', row, re.DOTALL | re.IGNORECASE)
        cells = [_strip(c).replace('\n', ' ') or ' ' for c in cells]
        md_rows.append('| ' + ' | '.join(cells) + ' |')
        if i == 0:
            md_rows.append('| ' + ' | '.join(['---'] * len(cells)) + ' |')
    return '\n' + '\n'.join(md_rows) + '\n'


if __name__ == '__main__':
    print(html2md(sys.stdin.read()))
