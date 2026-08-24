"""Tests for intake/web-page/html2md.py."""
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "html2md.py"
sys.path.insert(0, str(SCRIPT.parent))

from html2md import html2md  # noqa: E402


def test_headings_become_atx():
    assert html2md("<h1>Title</h1>") == "# Title"
    assert html2md("<h3>Sub</h3>") == "### Sub"


def test_script_and_style_bodies_are_dropped():
    out = html2md("<p>keep</p><script>var x = 1;</script><style>a{color:red}</style>")
    assert "keep" in out
    assert "var x" not in out
    assert "color:red" not in out


def test_links_become_inline_markdown():
    assert html2md('<a href="https://e.com">text</a>') == "[text](https://e.com)"


def test_emphasis_inside_a_link_label_is_preserved():
    # Inline formatting is converted before links, so the label keeps its
    # emphasis as markdown. What must never survive is raw HTML.
    out = html2md('<a href="/x"><strong>bold</strong></a>')
    assert out == "[**bold**](/x)"
    assert "<" not in out


def test_entities_are_decoded():
    assert html2md("<p>a &amp; b &lt;c&gt; &quot;d&quot;</p>") == 'a & b <c> "d"'


def test_table_gets_a_header_separator_row():
    html = "<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>"
    assert html2md(html) == "| A | B |\n| --- | --- |\n| 1 | 2 |"


def test_empty_table_cell_is_not_collapsed():
    # A blank cell must still occupy its column or the row misaligns.
    html = "<table><tr><td>1</td><td></td></tr></table>"
    assert html2md(html) == "| 1 |   |\n| --- | --- |"


def test_table_with_no_rows_yields_nothing():
    # Known limitation: the whole <table> is replaced, so a caption on a
    # row-less table is dropped with it. Degenerate input, documented not fixed.
    assert html2md("<table><caption>x</caption></table>") == ""


def test_list_items_become_dashes():
    out = html2md("<ul><li>one</li><li>two</li></ul>")
    assert out == "- one\n- two"


def test_runs_of_blank_lines_are_collapsed():
    out = html2md("<p>a</p><p>b</p>")
    assert "\n\n\n" not in out
    assert out == "a\n\nb"


def test_unknown_tags_are_stripped_but_text_survives():
    assert html2md("<div><span>text</span></div>") == "text"


def test_reads_stdin_and_writes_stdout():
    r = subprocess.run(
        [sys.executable, str(SCRIPT)],
        input="<h1>Hi</h1>",
        capture_output=True,
        text=True,
        check=True,
    )
    assert r.stdout.strip() == "# Hi"


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
