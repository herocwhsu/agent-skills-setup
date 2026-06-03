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
import urllib.parse
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
        label = m.group(1)
        title = urllib.parse.unquote(m.group(2))  # decode %28 → (, etc.
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
