#!/usr/bin/env python3
"""
push.py — push XHTML to a Confluence page (update or create).

Reads credentials from environment:
    CONFLUENCE_PASS — Basic Auth password OR PAT. Auto-detected.

Update mode (default):
    Reads --meta-file for pageId/version. GETs current version, aborts
    if it has moved since the meta.json was written, otherwise PUTs the
    new XHTML with version bumped by 1. On success, rewrites meta.json
    with the new version.

Create mode (--create):
    POSTs a new page with --space, --parent, --title, and the XHTML
    body. After success, writes a new meta.json next to --md-file.

Exit codes:
    0  success
    2  argument or input error
    3  auth failed (401)
    4  page not found (404)
    5  version conflict (the abort case)
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


def get_remote_version(host: str, page_id: str, auth: str) -> int:
    status, data = http_json(
        "GET",
        f"{base_url(host)}/rest/api/content/{page_id}?expand=version",
        headers={"Accept": "application/json", "Authorization": auth},
    )
    if status == 401:
        raise SystemExit(("auth failed reading version", 3))
    if status == 404:
        raise SystemExit((f"page {page_id} not found", 4))
    if status != 200 or not isinstance(data, dict):
        raise SystemExit((f"unexpected GET status {status}: {data}", 6))
    return int(data["version"]["number"])


def update(args: argparse.Namespace, secret: str) -> int:
    with open(args.meta_file) as f:
        meta = json.load(f)
    with open(args.xhtml, encoding="utf-8") as f:
        xhtml = f.read()

    page_id = meta["pageId"]
    stored_version = int(meta["version"])
    title = meta["title"]
    auth = auth_header(args.user, secret)

    try:
        live_version = get_remote_version(args.host, page_id, auth)
    except SystemExit as e:
        msg, code = e.args[0]
        print(f"ERROR: {msg}", file=sys.stderr)
        return code

    if live_version != stored_version:
        print(
            f"ERROR: page #{page_id} moved from v{stored_version} to v{live_version} since fetch.\n"
            f"Run /confluence-fetch {page_id} to pick up changes, then re-apply your edits.",
            file=sys.stderr,
        )
        return 5

    payload = json.dumps({
        "id": page_id,
        "type": "page",
        "title": title,
        "version": {"number": stored_version + 1},
        "body": {"storage": {"value": xhtml, "representation": "storage"}},
    }).encode()

    status, data = http_json(
        "PUT",
        f"{base_url(args.host)}/rest/api/content/{page_id}",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": auth,
        },
        body=payload,
    )

    if status == 401:
        print("ERROR: auth failed on PUT", file=sys.stderr)
        return 3
    if status == 409:
        print("ERROR: 409 conflict on PUT — another writer raced us. Re-fetch.", file=sys.stderr)
        return 5
    if status not in (200, 201):
        print(f"ERROR: PUT failed with {status}: {data}", file=sys.stderr)
        return 6

    new_version = int(data["version"]["number"]) if isinstance(data, dict) else stored_version + 1
    meta["version"] = new_version
    with open(args.meta_file, "w") as f:
        json.dump(meta, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"Updated page #{page_id} → v{new_version}")
    return 0


def create(args: argparse.Namespace, secret: str) -> int:
    with open(args.xhtml, encoding="utf-8") as f:
        xhtml = f.read()
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

    meta = {
        "pageId": data["id"],
        "version": int(data["version"]["number"]),
        "space": args.space,
        "ancestor": args.parent or "",
        "title": args.title,
        "host": args.host,
        "anchors": {},
    }
    out_meta = args.md_file + ".meta.json" if not args.out_meta else args.out_meta
    with open(out_meta, "w") as f:
        json.dump(meta, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"Created page #{data['id']} ({args.title}) → meta saved to {out_meta}")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--create", action="store_true")
    parser.add_argument("--meta-file")
    parser.add_argument("--xhtml", required=True)
    parser.add_argument("--md-file")
    parser.add_argument("--out-meta")
    parser.add_argument("--space")
    parser.add_argument("--parent")
    parser.add_argument("--title")
    args = parser.parse_args(argv)

    secret = os.environ.get("CONFLUENCE_PASS", "")
    if not secret:
        print("ERROR: CONFLUENCE_PASS env var not set", file=sys.stderr)
        return 2

    if args.create:
        for required in ("space", "title", "md_file"):
            if not getattr(args, required):
                print(f"ERROR: --create requires --{required.replace('_', '-')}", file=sys.stderr)
                return 2
        return create(args, secret)

    if not args.meta_file:
        print("ERROR: update mode requires --meta-file", file=sys.stderr)
        return 2
    return update(args, secret)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
