#!/usr/bin/env python3
"""
push.py — create a new Confluence page from an XHTML body.

Reads credentials from environment:
    CONFLUENCE_PASS — Basic Auth password OR PAT. Auto-detected.

POSTs a new page with --space, --parent, --title, and the XHTML body.
On success, prints a single JSON line to stdout describing the new
page: ``{"id":"NNN","version":1,"_links":{...}}``. The caller (e.g.
tree_upload.py) parses this to learn the new page id for pass-2 link
rewriting.

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
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


PAT_PATTERN = re.compile(r"^[A-Za-z0-9_=\-]{30,}$")


def base_url(host: str) -> str:
    """`host` is either a bare hostname (https assumed) or a full base URL."""
    return host if host.startswith(("http://", "https://")) else f"https://{host}"


def auth_header(user: str, secret: str) -> str:
    """Basic Auth by default, Bearer if the secret looks like a PAT."""
    if PAT_PATTERN.match(secret) and ":" not in secret:
        return f"Bearer {secret}"
    import base64
    token = base64.b64encode(f"{user}:{secret}".encode()).decode()
    return f"Basic {token}"


def http_json(method: str, url: str, *, headers: dict, body: bytes | None = None) -> tuple[int, dict | str]:
    req = urllib.request.Request(url, method=method, data=body, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            data = resp.read().decode()
            try:
                return resp.status, json.loads(data)
            except json.JSONDecodeError:
                return resp.status, data
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(body_text)
        except json.JSONDecodeError:
            return e.code, body_text


def create(args: argparse.Namespace, secret: str) -> int:
    try:
        with open(args.xhtml, encoding="utf-8") as f:
            xhtml = f.read()
    except OSError as e:
        print(f"ERROR: cannot read --xhtml file {args.xhtml!r}: {e}", file=sys.stderr)
        return 2
    auth = auth_header(args.user, secret)

    payload_dict: dict = {
        "type": "page",
        "title": args.title,
        "space": {"key": args.space},
        "body": {"storage": {"value": xhtml, "representation": "storage"}},
    }
    if args.parent:
        payload_dict["ancestors"] = [{"id": args.parent}]

    status, data = http_json(
        "POST",
        f"{base_url(args.host)}/rest/api/content",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": auth,
        },
        body=json.dumps(payload_dict).encode(),
    )

    if status == 401:
        print("ERROR: auth failed on POST", file=sys.stderr)
        return 3
    if status not in (200, 201):
        print(f"ERROR: POST failed with {status}: {data}", file=sys.stderr)
        return 6

    if not isinstance(data, dict):
        print(f"ERROR: unexpected POST body: {data}", file=sys.stderr)
        return 6

    page_id = data.get("id")
    version_block = data.get("version") or {}
    version_num = version_block.get("number") if isinstance(version_block, dict) else None
    if not page_id or version_num is None:
        print(f"ERROR: POST response missing id/version: {data}", file=sys.stderr)
        return 6

    result = {
        "id": page_id,
        "version": int(version_num),
        "_links": data.get("_links", {}),
    }
    print(json.dumps(result))
    print(f"Created page #{page_id} ({args.title})", file=sys.stderr)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--xhtml", required=True)
    parser.add_argument("--space", required=True)
    parser.add_argument("--parent")
    parser.add_argument("--title", required=True)
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

    return create(args, secret)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
