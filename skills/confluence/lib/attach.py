#!/usr/bin/env python3
"""
attach.py — upload local files as Confluence attachments on a page.

Workflow:
  For each path in --files:
    - 100MB pre-check.
    - POST /rest/api/content/{pageId}/child/attachment (multipart,
      X-Atlassian-Token: nocheck mandatory).
    - Use Path(filename).name as the multipart filename, so any leading
      directory components are stripped (path-traversal safety).

The migration flow already produces markdown shaped as
``![alt](./<dir>/<filename>)`` and the encoder converts that into
``<ac:image>`` directly — attach.py only uploads the binaries.

Reads credential via cred_provider.resolve_credential() — env var first, keychain fallback. PAT auto-detected (same as push.py).

Exit codes:
    0  success — every file uploaded
    2  argument or input error
    3  auth failed (401)
    6  one or more uploads failed (unless --continue-on-error,
       in which case 0 is returned and individual failures are
       printed to stderr)
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
from pathlib import Path


PAT_PATTERN = re.compile(r"^[A-Za-z0-9_=\-]{30,}$")
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
        raise SystemExit((f"file {file_path} is {size} bytes, exceeds 100MB limit", 6))

    with open(file_path, "rb") as f:
        content = f.read()

    # Path(filename).name strips any directory components — basename only
    # reaches the server. Mirrors the path-traversal safety used in
    # tree_fetch.py.
    filename = Path(file_path).name
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
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--page-id", required=True)
    parser.add_argument("--files", nargs="+", required=True)
    parser.add_argument("--continue-on-error", action="store_true")
    args = parser.parse_args(argv)

    sys.path.insert(0, str(Path(__file__).parent))
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
    failed = 0
    uploaded = 0

    for file_path in args.files:
        if not os.path.isfile(file_path):
            print(f"WARN: skipping missing file: {file_path}", file=sys.stderr)
            failed += 1
            if args.continue_on_error:
                continue
            return 6

        try:
            upload(args.host, args.page_id, file_path, auth)
        except SystemExit as e:
            arg = e.args[0]
            if isinstance(arg, tuple):
                msg, code = arg
                print(f"ERROR: {msg}", file=sys.stderr)
            else:
                msg, code = str(arg), 6
                print(f"ERROR: {msg}", file=sys.stderr)
            failed += 1
            if code == 3:
                # auth failures are fatal regardless of --continue-on-error
                return 3
            if args.continue_on_error:
                continue
            return code

        uploaded += 1
        print(f"  uploaded {Path(file_path).name}", file=sys.stderr)

    print(f"Uploaded {uploaded} attachment(s); {failed} failed.", file=sys.stderr)
    if failed and not args.continue_on_error:
        return 6
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
