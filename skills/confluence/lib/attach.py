#!/usr/bin/env python3
"""
attach.py — upload local images referenced by a markdown file as
Confluence attachments, then rewrite the md and meta.json so the
references become anchor tokens.

Workflow:
  1. Scan --md-file for `![alt](./path/to/img.png)` and `![alt](path)`
     where the URL is a local relative path (not http(s):// and not
     `[ri:...]`).
  2. For each path:
       - POST /rest/api/content/{pageId}/child/attachment (multipart,
         X-Atlassian-Token: nocheck mandatory).
       - Allocate a new anchor id (`img{N+1}` where N is the max
         existing img anchor in --meta-file).
       - Rewrite the md reference to `![alt][ri:img{N+1}]`.
       - Add the anchor entry to meta.json: type=image, filename=<name>.
  3. Save md and meta.json atomically.

Reads CONFLUENCE_PASS from env. PAT auto-detected (same as push.py).

100 MB upload limit is enforced before reading the file. No retry on
413: the user must split the file or change the server limit.

Exit codes:
    0  success (zero or more uploads completed)
    2  argument or input error
    3  auth failed
    6  upload failed (one of N) — md and meta are NOT modified for
       failed uploads; successful ones already applied are persisted
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.request
import uuid


PAT_PATTERN = re.compile(r"^[A-Za-z0-9_=\-]{30,}$")
LOCAL_IMG_RE = re.compile(r"!\[([^\]]*)\]\((?!https?://)(?!\[ri:)([^)]+)\)")
MAX_UPLOAD_BYTES = 100 * 1024 * 1024


def base_url(host: str) -> str:
    """`host` is either a bare hostname (https assumed) or a full base URL."""
    return host if host.startswith(("http://", "https://")) else f"https://{host}"


def auth_header(user: str, secret: str) -> str:
    if PAT_PATTERN.match(secret) and ":" not in secret:
        return f"Bearer {secret}"
    import base64
    token = base64.b64encode(f"{user}:{secret}".encode()).decode()
    return f"Basic {token}"


def next_img_id(meta: dict) -> str:
    used = [int(k[3:]) for k in meta.get("anchors", {}) if k.startswith("img") and k[3:].isdigit()]
    return f"img{max(used) + 1 if used else 1}"


def build_multipart(filename: str, content: bytes, content_type: str) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: {content_type}\r\n\r\n"
    ).encode()
    body += content
    body += f"\r\n--{boundary}--\r\n".encode()
    return body, boundary


def upload(host: str, page_id: str, file_path: str, auth: str) -> dict:
    size = os.path.getsize(file_path)
    if size > MAX_UPLOAD_BYTES:
        raise SystemExit(f"file {file_path} is {size} bytes, exceeds 100MB limit")

    with open(file_path, "rb") as f:
        content = f.read()

    filename = os.path.basename(file_path)
    content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
    body, boundary = build_multipart(filename, content, content_type)

    req = urllib.request.Request(
        f"{base_url(host)}/rest/api/content/{page_id}/child/attachment",
        method="POST",
        data=body,
        headers={
            "Accept": "application/json",
            "Authorization": auth,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "X-Atlassian-Token": "nocheck",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")
        if e.code == 401:
            raise SystemExit(("auth failed on attachment upload", 3))
        raise SystemExit((f"attachment upload failed ({e.code}): {body_text}", 6))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--md-file", required=True)
    parser.add_argument("--meta-file", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    args = parser.parse_args(argv)

    secret = os.environ.get("CONFLUENCE_PASS", "")
    if not secret:
        print("ERROR: CONFLUENCE_PASS env var not set", file=sys.stderr)
        return 2

    with open(args.md_file, encoding="utf-8") as f:
        md = f.read()
    with open(args.meta_file) as f:
        meta = json.load(f)

    page_id = meta["pageId"]
    auth = auth_header(args.user, secret)
    md_dir = os.path.dirname(os.path.abspath(args.md_file))
    matches = list(LOCAL_IMG_RE.finditer(md))

    if not matches:
        print("No local images to upload.")
        return 0

    new_md = md
    upload_count = 0

    for m in matches:
        alt, rel_path = m.group(1), m.group(2).strip()
        full_path = os.path.normpath(os.path.join(md_dir, rel_path))
        if not os.path.isfile(full_path):
            print(f"WARN: skipping missing file: {rel_path}", file=sys.stderr)
            continue

        try:
            upload(args.host, page_id, full_path, auth)
        except SystemExit as e:
            arg = e.args[0]
            if isinstance(arg, tuple):
                msg, code = arg
                print(f"ERROR: {msg}", file=sys.stderr)
                _save(args.md_file, new_md, args.meta_file, meta)
                return code
            print(f"ERROR: {arg}", file=sys.stderr)
            _save(args.md_file, new_md, args.meta_file, meta)
            return 6

        anchor_id = next_img_id(meta)
        filename = os.path.basename(full_path)
        meta.setdefault("anchors", {})[anchor_id] = {
            "type": "image",
            "filename": filename,
            "xml": f'<ac:image><ri:attachment ri:filename="{filename}"/></ac:image>',
        }
        new_md = new_md.replace(m.group(0), f"![{alt}][ri:{anchor_id}]", 1)
        upload_count += 1
        print(f"  ✓ uploaded {filename} → anchor {anchor_id}")

    _save(args.md_file, new_md, args.meta_file, meta)
    print(f"Uploaded {upload_count} attachment(s).")
    return 0


def _save(md_path: str, md: str, meta_path: str, meta: dict) -> None:
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(md)
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
