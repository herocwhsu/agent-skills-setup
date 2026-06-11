#!/usr/bin/env python3
"""
Pass-2 resume script for interrupted Confluence tree uploads.

Reads stub_map.json and manifest.json from the fetch dir.
Checks current page version via API — skips pages already on version 2+.
On XHTML conversion failure, uploads a placeholder with link to original.

stub_map.json format: { "<source_page_id>": "<new_confluence_page_id>" }
Build it from the live tree after a partial upload using page titles as keys.

Usage:
    python3 upload_resume.py --fetch-dir <path> [--dry-run]
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

SKILL_DIR = Path.home() / ".claude/skills/utils/confluence-tree/lib"
sys.path.insert(0, str(SKILL_DIR))

import md_to_xhtml
import attach
import tempfile

FETCH_DIR = Path("docs/confluence/2026-06-09-296989759")
HOST = "confluence.vivotek.com"
USER = "hero.hsu"
BASE = f"https://{HOST}/rest/api"


def get_password() -> str:
    import subprocess
    svc = "agent-skills-setup:confluence-https---confluence-vivotek-com"
    r = subprocess.run(
        ["security", "find-generic-password", "-s", svc, "-a", USER, "-w"],
        capture_output=True, text=True
    )
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit(f"ERROR: credential not found for {svc}")
    return r.stdout.strip()


_PASS = None

def auth_header() -> str:
    global _PASS
    if _PASS is None:
        _PASS = get_password()
    return "Basic " + base64.b64encode(f"{USER}:{_PASS}".encode()).decode()


def get_page_version(page_id: str) -> int:
    url = f"{BASE}/content/{page_id}?expand=version"
    req = urllib.request.Request(url, headers={
        "Authorization": auth_header(), "Accept": "application/json"
    })
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())["version"]["number"]
    except Exception:
        return 0


def put_content(page_id: str, title: str, xhtml_body: str, version: int) -> None:
    payload = json.dumps({
        "version": {"number": version},
        "title": title,
        "type": "page",
        "body": {"storage": {"value": xhtml_body, "representation": "storage"}}
    }).encode()
    url = f"{BASE}/content/{page_id}"
    req = urllib.request.Request(url, data=payload, method="PUT", headers={
        "Authorization": auth_header(),
        "Content-Type": "application/json",
        "Accept": "application/json",
    })
    with urllib.request.urlopen(req) as r:
        r.read()


def upload_page(page: dict, new_id: str, dry_run: bool) -> bool:
    """Upload content for one page. Returns True on success."""
    md_path = FETCH_DIR / page["relative_path"]
    if not md_path.exists():
        print(f"  SKIP (no file): {page['title']}")
        return True

    # Read and strip frontmatter
    raw = md_path.read_text(encoding="utf-8")
    if raw.startswith("---"):
        parts = raw.split("---", 2)
        body_md = parts[2].lstrip("\n") if len(parts) >= 3 else raw
    else:
        body_md = raw

    source_url = page.get("source_url", "")

    # Try XHTML conversion using temp files (matching tree_upload.py approach)
    xhtml_body = None
    try:
        diagrams_path = md_path.parent / (md_path.stem + ".diagrams.json")
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            in_path = td_path / "in.md"
            out_path = td_path / "out.xml"
            in_path.write_text(body_md, encoding="utf-8")
            argv = ["--md-file", str(in_path), "--out", str(out_path)]
            if diagrams_path.exists():
                argv += ["--diagrams-file", str(diagrams_path)]
            rc = md_to_xhtml.main(argv)
            if rc == 0:
                xhtml_body = out_path.read_text(encoding="utf-8")
            else:
                print(f"  WARN md_to_xhtml rc={rc} for: {page['title']}")
    except Exception as e:
        print(f"  WARN conversion error ({page['title']}): {e}")

    if xhtml_body is None:
        # Fallback: placeholder with link to original
        xhtml_body = (
            f'<p><strong>Note:</strong> Content could not be automatically migrated '
            f'due to formatting. '
        )
        if source_url:
            xhtml_body += f'See original: <a href="{source_url}">{source_url}</a>'
        xhtml_body += "</p>"

    if dry_run:
        print(f"  DRY-RUN upload: {page['title']} → #{new_id}")
        return True

    try:
        put_content(new_id, page["title"], xhtml_body, version=2)
        # Upload attachments if present
        attachments_dir = md_path.parent / (md_path.stem + ".attachments")
        if attachments_dir.exists():
            auth = auth_header()
            for att in attachments_dir.iterdir():
                if att.is_file():
                    attach.upload(HOST, new_id, str(att), auth)
        return True
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        if e.code == 400 and "xhtml" in err_body.lower():
            # Retry with fallback placeholder
            print(f"  WARN XHTML rejected, uploading placeholder for: {page['title']}")
            fallback = (
                f'<p><strong>Note:</strong> Content could not be automatically migrated '
                f'due to formatting. '
            )
            if source_url:
                fallback += f'See original: <a href="{source_url}">{source_url}</a>'
            fallback += "</p>"
            try:
                put_content(new_id, page["title"], fallback, version=2)
                return True
            except Exception as e2:
                print(f"  ERROR fallback also failed for {page['title']}: {e2}")
                return False
        else:
            print(f"  ERROR HTTP {e.code} for {page['title']}: {err_body[:200]}")
            return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--fetch-dir", default="docs/confluence/2026-06-09-296989759",
                        help="Path to the fetch directory containing manifest.json and stub_map.json")
    args = parser.parse_args()

    global FETCH_DIR
    FETCH_DIR = Path(args.fetch_dir)

    manifest = json.loads((FETCH_DIR / "manifest.json").read_text())
    stub_map = json.loads((FETCH_DIR / "stub_map.json").read_text())
    pages = manifest["pages"]

    print(f"Total pages: {len(pages)}")
    print(f"Stub map entries: {len(stub_map)}")
    if args.dry_run:
        print("DRY RUN — no writes.\n")

    skipped = uploaded = failed = 0

    for page in pages:
        src_id = page["page_id"]
        new_id = stub_map.get(src_id)
        if not new_id:
            print(f"  SKIP (not in stub_map): [{src_id}] {page['title']}")
            skipped += 1
            continue

        # Check if already uploaded (version >= 2)
        if not args.dry_run:
            ver = get_page_version(new_id)
            if ver >= 2:
                print(f"  SKIP (already v{ver}): {page['title']}")
                skipped += 1
                continue

        print(f"  Upload: {page['title']} (src:{src_id} → new:{new_id})")
        ok = upload_page(page, new_id, args.dry_run)
        if ok:
            uploaded += 1
        else:
            failed += 1
        if not args.dry_run:
            time.sleep(0.2)

    print(f"\nDone. uploaded={uploaded} skipped={skipped} failed={failed}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
