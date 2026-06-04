#!/usr/bin/env python3
"""tree_fetch.py — recursively fetch a Confluence page subtree as markdown.

CLI:
    python3 tree_fetch.py --host <host> --user <user> --root-id <id> --out-dir <dir>

Reads CONFLUENCE_PASS from env (Basic Auth password OR PAT, auto-detected
exactly like push.py).

Behavior:
  - Pre-order, depth-first walk rooted at --root-id.
  - Each page → markdown with YAML frontmatter; attachments saved under a
    sibling <basename>.attachments/ directory; diagrams (drawio/gliffy)
    written as <basename>.diagrams.json.
  - Pages returning 403 are logged and skipped (subtree pruned).
  - Attachments larger than 100 MB are warned and skipped.
  - Final <out-dir>/manifest.json lists every saved page.

Path layout (relative to --out-dir):
    Root            _root.md
    Leaf page       <parent-dir>/<slug>.md
    Branch page     <parent-dir>/<slug>/_index.md

Exit codes:
    0  success
    2  argument or input error
    3  auth failed
    4  page not found
    6  other HTTP error
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Sibling import: lets `python3 lib/tree_fetch.py` reach push / xhtml_to_md
# without making lib/ a package.
sys.path.insert(0, str(Path(__file__).parent))
from push import auth_header, base_url  # noqa: E402
from xhtml_to_md import convert as xhtml_to_md_convert  # noqa: E402

PAGE_LIMIT = 25
ATTACH_LIMIT = 25
MAX_DOWNLOAD_BYTES = 100 * 1024 * 1024
SLUG_MAX = 40


def slugify(title: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", (title or "").lower()).strip("-")
    if not s:
        return "untitled"
    return s[:SLUG_MAX].rstrip("-") or "untitled"


def _escape_yaml(s: str) -> str:
    """Escape a string for use as a double-quoted YAML scalar value.

    Constraint: the output must round-trip through link_rewrite.parse_frontmatter,
    which uses a naive ``.strip('"')`` (no escape decoding). So we cannot emit
    backslash-escapes. Instead, substitute the YAML-breaking characters with
    safe equivalents:
      - double quote → single quote
      - backslash → forward slash
      - newlines / carriage returns → space
    """
    return (
        (s or "")
        .replace("\\", "/")
        .replace('"', "'")
        .replace("\r", " ")
        .replace("\n", " ")
    )


def http_get_json(url: str, auth: str) -> tuple[int, object]:
    req = urllib.request.Request(
        url, method="GET",
        headers={"Accept": "application/json", "Authorization": auth},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, raw
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(body_text)
        except json.JSONDecodeError:
            return e.code, body_text


def http_get_bytes(url: str, auth: str) -> tuple[int, bytes]:
    req = urllib.request.Request(url, method="GET", headers={"Authorization": auth})
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def fetch_page(host: str, page_id: str, auth: str):
    """Returns the page dict, or None on 403. Raises SystemExit on other errors."""
    url = (f"{base_url(host)}/rest/api/content/{page_id}"
           "?expand=body.storage,version,space,ancestors")
    status, data = http_get_json(url, auth)
    if status == 200 and isinstance(data, dict):
        return data
    if status == 403:
        print(f"WARN: skipped page {page_id} (403)", file=sys.stderr)
        return None
    if status == 401:
        raise SystemExit(("auth failed reading page", 3))
    if status == 404:
        raise SystemExit((f"page {page_id} not found", 4))
    raise SystemExit((f"GET page {page_id} failed ({status}): {data}", 6))


def list_children(host: str, page_id: str, auth: str) -> list[dict]:
    """Paginated child-page listing. Returns [] on 403."""
    items: list[dict] = []
    start = 0
    while True:
        url = (f"{base_url(host)}/rest/api/content/{page_id}/child/page"
               f"?start={start}&limit={PAGE_LIMIT}")
        status, data = http_get_json(url, auth)
        if status == 403:
            print(f"WARN: skipped children of page {page_id} (403)", file=sys.stderr)
            return items
        if status != 200 or not isinstance(data, dict):
            raise SystemExit((f"GET children of {page_id} failed ({status}): {data}", 6))
        results = data.get("results", []) or []
        items.extend(results)
        if len(results) < PAGE_LIMIT:
            break
        start += PAGE_LIMIT
    return items


def list_attachments(host: str, page_id: str, auth: str) -> list[dict]:
    items: list[dict] = []
    start = 0
    while True:
        url = (f"{base_url(host)}/rest/api/content/{page_id}/child/attachment"
               f"?start={start}&limit={ATTACH_LIMIT}&expand=metadata.mediaType")
        status, data = http_get_json(url, auth)
        if status == 403:
            print(f"WARN: skipped attachments of page {page_id} (403)", file=sys.stderr)
            return items
        if status != 200 or not isinstance(data, dict):
            raise SystemExit((f"GET attachments of {page_id} failed ({status}): {data}", 6))
        results = data.get("results", []) or []
        items.extend(results)
        if len(results) < ATTACH_LIMIT:
            break
        start += ATTACH_LIMIT
    return items


def download_attachment(host: str, page_id: str, attach: dict,
                        dest_dir: Path, auth: str) -> bool:
    """Download one attachment to dest_dir. Returns True if saved."""
    raw_name = attach.get("title") or attach.get("id") or "unknown"
    # Confluence attachment titles are user-controlled. A title containing
    # "/", "\", or ".." would let the saved file escape the attachments
    # directory. Reject anything where stripping path components changes
    # the name, plus the obvious "."/"..".
    filename = Path(raw_name).name
    if (not filename or filename in {".", ".."}
            or filename != raw_name):
        print(f"WARN: attachment with invalid name {raw_name!r}, skipping",
              file=sys.stderr)
        return False
    declared_size = (attach.get("extensions") or {}).get("fileSize")
    if declared_size is None:
        print(f"  → no declared fileSize for {filename}; relying on "
              "post-download check", file=sys.stderr)
    elif isinstance(declared_size, int) and declared_size > MAX_DOWNLOAD_BYTES:
        print(f"WARN: skipping {filename}: declared {declared_size} bytes "
              "> 100MB limit", file=sys.stderr)
        return False
    download_link = (attach.get("_links") or {}).get("download") or \
        f"/rest/api/content/{page_id}/child/attachment/{attach.get('id')}/download"
    url = base_url(host) + download_link
    status, body = http_get_bytes(url, auth)
    if status != 200:
        print(f"WARN: failed to download {filename} ({status})", file=sys.stderr)
        return False
    if len(body) > MAX_DOWNLOAD_BYTES:
        print(f"WARN: skipping {filename} ({len(body)} bytes, exceeds 100MB)",
              file=sys.stderr)
        return False
    dest_dir.mkdir(parents=True, exist_ok=True)
    (dest_dir / filename).write_bytes(body)
    return True


def write_markdown(
    md_path: Path,
    *,
    page: dict,
    host: str,
    fetched_at: str,
    basename: str,
    body_md: str,
    has_attachments: bool,
    has_diagrams: bool,
) -> None:
    webui = (page.get("_links") or {}).get("webui") or ""
    source_url = (base_url(host) + webui) if webui else ""
    version = int((page.get("version") or {}).get("number", 0))
    lines = [
        "---",
        f'source_page_id: "{page["id"]}"',
        f'source_title: "{_escape_yaml(page.get("title", ""))}"',
        f'source_url: "{source_url}"',
        f"source_version: {version}",
        f'fetched_at: "{fetched_at}"',
    ]
    if has_attachments:
        lines.append(f'attachments_dir: "./{basename}.attachments"')
    if has_diagrams:
        lines.append(f'diagrams_file: "./{basename}.diagrams.json"')
    lines.append("---")
    md_path.parent.mkdir(parents=True, exist_ok=True)
    md_path.write_text("\n".join(lines) + "\n\n" + body_md, encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--root-id", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args(argv)

    from cred_provider import resolve_credential
    secret = resolve_credential(args.host, args.user)
    if not secret:
        print(
            "ERROR: no Confluence credential found.\n"
            "  Run: bash scripts/credentials/service.sh confluence add",
            file=sys.stderr,
        )
        return 2

    auth = auth_header(args.user, secret)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    fetched_at = datetime.date.today().isoformat()
    host_base = base_url(args.host)

    manifest_pages: list[dict] = []
    sibling_slugs: dict[str, set[str]] = {}
    state = {"root_title": ""}

    def visit(page_id: str, parent_id: str | None,
              parent_rel_dir: str, depth: int) -> None:
        page = fetch_page(args.host, page_id, auth)
        if page is None:
            return  # 403 — prune subtree
        children = list_children(args.host, page_id, auth)
        title = page.get("title", "")
        has_children = bool(children)

        if depth == 0:
            rel_md_path = "_root.md"
            page_rel_dir = ""
            basename = "_root"
            state["root_title"] = title
        else:
            base_slug = slugify(title)
            used = sibling_slugs.setdefault(parent_rel_dir, set())
            slug = base_slug
            n = 2
            while slug in used:
                slug = f"{base_slug}-{n}"
                n += 1
            used.add(slug)
            if has_children:
                page_rel_dir = f"{parent_rel_dir}/{slug}" if parent_rel_dir else slug
                rel_md_path = f"{page_rel_dir}/_index.md"
                basename = "_index"
            else:
                page_rel_dir = parent_rel_dir
                rel_md_path = (f"{parent_rel_dir}/{slug}.md"
                               if parent_rel_dir else f"{slug}.md")
                basename = slug

        body_storage = ((page.get("body") or {}).get("storage") or {}).get("value", "") or ""
        try:
            body_md, diagrams = xhtml_to_md_convert(
                body_storage,
                attachments_rel=f"./{basename}.attachments",
                base_url=host_base,
            )
        except Exception as exc:  # malformed XHTML — fall back to raw
            print(f"WARN: xhtml_to_md failed on page {page_id}: {exc}",
                  file=sys.stderr)
            body_md, diagrams = body_storage + "\n", {}

        attachments = list_attachments(args.host, page_id, auth)
        md_path = out_dir / rel_md_path
        attachments_dir = md_path.parent / f"{basename}.attachments"
        downloaded_any = False
        for att in attachments:
            if download_attachment(args.host, page_id, att, attachments_dir, auth):
                downloaded_any = True

        has_diagrams = bool(diagrams)
        if has_diagrams:
            diag_path = md_path.parent / f"{basename}.diagrams.json"
            diag_path.parent.mkdir(parents=True, exist_ok=True)
            diag_path.write_text(json.dumps(diagrams, indent=2) + "\n",
                                 encoding="utf-8")

        write_markdown(
            md_path,
            page=page, host=args.host, fetched_at=fetched_at,
            basename=basename, body_md=body_md,
            has_attachments=downloaded_any, has_diagrams=has_diagrams,
        )

        manifest_pages.append({
            "page_id": page_id,
            "title": title,
            "relative_path": rel_md_path,
            "parent_id": parent_id,
            "depth": depth,
        })

        for child in children:
            visit(child["id"], page_id, page_rel_dir, depth + 1)

    try:
        visit(args.root_id, None, "", 0)
    except SystemExit as e:
        arg = e.args[0] if e.args else None
        if isinstance(arg, tuple):
            msg, code = arg
            print(f"ERROR: {msg}", file=sys.stderr)
            return code
        raise

    manifest = {
        "root_id": args.root_id,
        "root_title": state["root_title"],
        "host": args.host,
        "fetched_at": fetched_at,
        "pages": manifest_pages,
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Fetched {len(manifest_pages)} page(s) → {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
