#!/usr/bin/env python3
"""tree_upload.py — two-pass uploader for a locally-edited Confluence tree.

CLI:
    python3 tree_upload.py --tree <local-dir> \\
                           --new-parent <id> \\
                           --space <KEY> \\
                           --host <host-or-base-url> \\
                           --user <user> \\
                           [--dry-run]

Reads CONFLUENCE_PASS from env (Basic Auth password OR PAT, auto-detected the
same way as push.py).

Behavior:
  Pass 1 — Stub creation
    Walk every page in the manifest's pre-order. For each page, POST a
    placeholder ``<p>migrated, content pending</p>`` so we learn its new id
    before any of its children are created. If any stub creation fails the
    upload aborts before pass 2 — no partial content writes.

  Pass 2 — Content
    For each page (same order), strip frontmatter, rewrite intra-tree
    ``wiki://page/<title>`` links into absolute ``<host>/pages/<new_id>``
    URLs (titles outside the tree pass through verbatim — link_rewrite.py
    leaves them as wiki:// for tree_upload to either fix or ignore). Then
    encode markdown → XHTML via md_to_xhtml.main, upload sibling
    ``<basename>.attachments/`` files via attach.upload, and PUT the
    encoded body. Stub version is always 1, so the content PUT uses
    version 2 with no conflict check.

Exit codes:
    0  success
    2  argument or input error
    3  auth failed (401)
    6  other HTTP error
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import time
import urllib.parse
from pathlib import Path

# Sibling import — lets `python3 lib/tree_upload.py` reach push/attach/etc
# without making lib/ a package.
sys.path.insert(0, str(Path(__file__).parent))
from push import auth_header, base_url, http_json  # noqa: E402
from attach import upload as attach_upload  # noqa: E402
from link_rewrite import WIKI_LINK_RE, parse_frontmatter  # noqa: E402
import md_to_xhtml  # noqa: E402


def load_pages(tree: Path) -> list[dict]:
    """Return the manifest's `pages` list (pre-order DFS as written by
    tree_fetch.py) with each entry's title overridden from the on-disk
    frontmatter `source_title` (the on-disk tree is the source of truth,
    not the manifest — the user may have edited frontmatter between
    fetch and upload). Aborts if the on-disk `source_page_id` disagrees
    with the manifest's `page_id`.
    """
    manifest_path = tree / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit(
            (f"manifest.json not found in {tree}; was it written by tree_fetch?", 2)
        )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    pages = manifest.get("pages", [])

    for p in pages:
        md_path = tree / p["relative_path"]
        if not md_path.is_file():
            raise SystemExit(
                (f"tree page {p['relative_path']} missing on disk", 2)
            )
        fm = parse_frontmatter(md_path.read_text(encoding="utf-8"))
        on_disk_id = fm.get("source_page_id")
        on_disk_title = fm.get("source_title")
        if on_disk_id and on_disk_id != p["page_id"]:
            raise SystemExit((
                f"source_page_id mismatch in {p['relative_path']}: "
                f"manifest says {p['page_id']}, frontmatter says {on_disk_id}",
                2,
            ))
        if on_disk_title:
            p["title"] = on_disk_title  # prefer on-disk; user may have edited

    return pages


def stub_create(host: str, user: str, secret: str, space: str,
                parent_id: str, title: str) -> str:
    """POST a placeholder page. Return the new page id."""
    auth = auth_header(user, secret)
    payload = json.dumps({
        "type": "page",
        "title": title,
        "space": {"key": space},
        "ancestors": [{"id": parent_id}],
        "body": {
            "storage": {
                "value": "<p>migrated, content pending</p>",
                "representation": "storage",
            }
        },
    }).encode()
    status, data = http_json(
        "POST",
        f"{base_url(host)}/rest/api/content",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": auth,
        },
        body=payload,
    )
    if status == 401:
        raise SystemExit(("auth failed on stub create", 3))
    if status not in (200, 201):
        raise SystemExit((f"stub create failed ({status}): {data}", 6))
    if not isinstance(data, dict) or not data.get("id"):
        raise SystemExit((f"stub create response missing id: {data}", 6))
    return str(data["id"])


def update_page(host: str, user: str, secret: str, page_id: str, title: str,
                xhtml: str, version: int) -> None:
    """PUT the encoded XHTML to a page. Version is current+1 (always 2 here)."""
    auth = auth_header(user, secret)
    payload = json.dumps({
        "id": page_id,
        "type": "page",
        "title": title,
        "version": {"number": version},
        "body": {"storage": {"value": xhtml, "representation": "storage"}},
    }).encode()
    status, data = http_json(
        "PUT",
        f"{base_url(host)}/rest/api/content/{page_id}",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": auth,
        },
        body=payload,
    )
    if status == 401:
        raise SystemExit(("auth failed on PUT", 3))
    if status not in (200, 201):
        raise SystemExit((f"PUT failed ({status}): {data}", 6))


def rewrite_intra_tree_links(md: str, source_to_new_id: dict[str, str],
                             source_title_to_id: dict[str, str],
                             host_base_url: str) -> str:
    """Replace wiki://page/<title> with absolute URLs to newly-created pages.
    Titles not in the tree (or whose source page failed stub creation) pass
    through verbatim — they become broken wiki:// links the user fixes
    manually, which is preferable to a guessed wrong target.
    """
    def repl(m):
        label = m.group(1)
        title = urllib.parse.unquote(m.group(2))
        source_page_id = source_title_to_id.get(title)
        if source_page_id is None:
            return m.group(0)
        new_id = source_to_new_id.get(source_page_id)
        if new_id is None:
            return m.group(0)
        return f"[{label}]({host_base_url}/pages/{new_id})"
    return WIKI_LINK_RE.sub(repl, md)


def strip_frontmatter_body(text: str) -> str:
    """Return the body of the markdown file (everything after the YAML
    frontmatter). Mirrors md_to_xhtml.strip_frontmatter but returns body only.
    """
    if not text.startswith("---\n"):
        return text
    end = text.find("\n---\n", 4)
    if end == -1:
        return text
    return text[end + 5:]


def encode_md(md_text: str, diagrams_path: Path | None) -> str:
    """Run md_to_xhtml on a markdown string. Returns XHTML string.

    md_to_xhtml.main reads from --md-file. We use a temp dir so the input
    file and the output XHTML are auto-deleted on context exit.
    """
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        in_path = td_path / "in.md"
        out_path = td_path / "out.xml"
        in_path.write_text(md_text, encoding="utf-8")
        argv = ["--md-file", str(in_path), "--out", str(out_path)]
        if diagrams_path and diagrams_path.exists():
            argv += ["--diagrams-file", str(diagrams_path)]
        rc = md_to_xhtml.main(argv)
        if rc != 0:
            raise SystemExit((f"md_to_xhtml failed (rc={rc})", 6))
        return out_path.read_text(encoding="utf-8")


def upload_attachments_for_page(host: str, user: str, secret: str,
                                new_page_id: str, attachments_dir: Path) -> int:
    """Upload every file in the page's <basename>.attachments/ directory.
    Returns count of successful uploads. A single failed attachment WARNs
    and continues — manual fixup of one attachment is cheap, blocking the
    whole tree upload because of one bad file is not. Auth failures (401)
    re-raise so the whole upload aborts cleanly with exit 3.
    """
    if not attachments_dir.is_dir():
        return 0
    auth = auth_header(user, secret)
    count = 0
    for path in sorted(attachments_dir.iterdir()):
        if not path.is_file():
            continue
        try:
            attach_upload(base_url(host), new_page_id, str(path), auth)
            count += 1
        except SystemExit as e:
            arg = e.args[0]
            if isinstance(arg, tuple):
                msg, code = arg
            else:
                msg, code = str(arg), 6
            if code == 3:
                raise  # auth failures abort the whole upload
            print(f"  WARN: attachment upload failed for {path.name}: {msg}",
                  file=sys.stderr)
    return count


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tree", required=True)
    parser.add_argument("--new-parent", required=True)
    parser.add_argument("--space", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    tree = Path(args.tree)
    if not tree.is_dir():
        print(f"ERROR: --tree {args.tree!r} is not a directory", file=sys.stderr)
        return 2

    secret = os.environ.get("CONFLUENCE_PASS", "")
    if not secret and not args.dry_run:
        print("ERROR: CONFLUENCE_PASS env var not set", file=sys.stderr)
        return 2

    try:
        pages = load_pages(tree)
    except SystemExit as e:
        arg = e.args[0]
        msg, code = arg if isinstance(arg, tuple) else (str(arg), 2)
        print(f"ERROR: {msg}", file=sys.stderr)
        return code

    if not pages:
        print("ERROR: no pages in manifest", file=sys.stderr)
        return 2

    # Build {source_title: source_page_id} from the manifest.
    source_title_to_id = {p["title"]: p["page_id"] for p in pages}

    started = time.monotonic()

    # ----- Pass 1: stubs -----
    source_to_new_id: dict[str, str] = {}
    if args.dry_run:
        print(f"DRY RUN: would create {len(pages)} stubs under parent "
              f"{args.new_parent} in space {args.space}")
        for p in pages:
            parent_label = (
                args.new_parent if p["parent_id"] is None
                else f"source #{p['parent_id']} (will be a new page)"
            )
            print(f"  stub: {p['title']!r} (source #{p['page_id']}) → "
                  f"under {parent_label}")
    else:
        print(f"Pass 1: creating {len(pages)} stubs...", file=sys.stderr)
        for p in pages:
            parent_id = (
                args.new_parent
                if p["parent_id"] is None or p["parent_id"] not in source_to_new_id
                else source_to_new_id[p["parent_id"]]
            )
            try:
                new_id = stub_create(
                    args.host, args.user, secret,
                    args.space, parent_id, p["title"],
                )
            except SystemExit as e:
                arg = e.args[0]
                msg, code = arg if isinstance(arg, tuple) else (str(arg), 6)
                print(f"ERROR: {msg}", file=sys.stderr)
                created_ids = list(source_to_new_id.values())
                print(
                    f"Pass 1 aborted. Stubs created so far: {created_ids}",
                    file=sys.stderr,
                )
                return code
            source_to_new_id[p["page_id"]] = new_id
            print(f"  stub: {p['title']} → #{new_id}", file=sys.stderr)

    # ----- Pass 2: content -----
    host_base = base_url(args.host)

    if args.dry_run:
        for p in pages:
            md_path = tree / p["relative_path"]
            if not md_path.is_file():
                print(f"  WARN: missing markdown for {p['title']}: {md_path}")
                continue
            md_text = md_path.read_text(encoding="utf-8")
            for m in WIKI_LINK_RE.finditer(md_text):
                title = urllib.parse.unquote(m.group(2))
                src_id = source_title_to_id.get(title)
                if src_id is None:
                    print(f"  link in {p['title']!r}: → wiki://page/{title} "
                          f"(UNRESOLVED — outside tree, passthrough)")
                else:
                    print(f"  link in {p['title']!r}: → {title!r} "
                          f"(would rewrite to source #{src_id})")
        return 0

    print(f"Pass 2: uploading content for {len(pages)} pages...",
          file=sys.stderr)
    attached_total = 0
    for p in pages:
        md_path = tree / p["relative_path"]
        text = md_path.read_text(encoding="utf-8")
        body = strip_frontmatter_body(text)

        body = rewrite_intra_tree_links(
            body, source_to_new_id, source_title_to_id, host_base,
        )

        diagrams_path = md_path.parent / (md_path.stem + ".diagrams.json")
        try:
            xhtml = encode_md(body, diagrams_path)
        except SystemExit as e:
            arg = e.args[0]
            msg, code = arg if isinstance(arg, tuple) else (str(arg), 6)
            print(f"ERROR encoding {p['title']}: {msg}", file=sys.stderr)
            return code

        attachments_dir = md_path.parent / (md_path.stem + ".attachments")
        new_id = source_to_new_id[p["page_id"]]
        try:
            attached_total += upload_attachments_for_page(
                args.host, args.user, secret, new_id, attachments_dir,
            )
        except SystemExit as e:
            arg = e.args[0]
            msg, code = arg if isinstance(arg, tuple) else (str(arg), 6)
            print(f"ERROR: attachment auth failure on {p['title']}: {msg}",
                  file=sys.stderr)
            return code

        try:
            update_page(args.host, args.user, secret, new_id, p["title"], xhtml, 2)
        except SystemExit as e:
            arg = e.args[0]
            msg, code = arg if isinstance(arg, tuple) else (str(arg), 6)
            print(f"ERROR updating {p['title']}: {msg}", file=sys.stderr)
            return code
        print(f"  content: {p['title']} → #{new_id}", file=sys.stderr)

    elapsed = time.monotonic() - started
    print(
        f"\nDone. Created {len(pages)} pages, uploaded {attached_total} "
        f"attachments in {elapsed:.1f}s.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
