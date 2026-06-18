#!/usr/bin/env python3
"""apidog-share-fetch — read endpoints from an Apidog public share link.

The Apidog public REST API ``/v1/shared-docs/<uuid>/export-openapi`` redirects
to docs (verified 2026-06-18); the MCP server has no branch support. The
share-link SPA's Remix loader (`<share-uuid>/api-<id>.data`) is the only
working read path for non-default branches.

This script decodes the Remix turbo-stream (positional refs of the form
``_N`` indexing a flat slot array) and extracts the endpoint contract.

Usage::

    apidog-share-fetch --share-uuid UUID --list
    apidog-share-fetch --share-uuid UUID --endpoint-id 37491818
    apidog-share-fetch --share-uuid UUID --path-prefix /auth

Output: JSON to stdout. Stable for stable inputs.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from typing import Any, Iterable

SHARE_HOST = "https://share.apidog.com"
USER_AGENT = "apidog-share-fetch/1.0 (+https://vivotek.atlassian.net/browse/HUM-17)"
TIMEOUT_S = 30


def _http_get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
        if resp.status != 200:
            raise RuntimeError(f"GET {url} returned {resp.status}")
        return resp.read()


def _resolve(slots: list[Any], idx: int, seen: frozenset[int] = frozenset(), depth: int = 0) -> Any:
    """Resolve slot ``idx`` from a Remix turbo-stream slot array.

    Slot values that are ``int`` reference another slot index. Dict keys of
    the form ``_N`` reference the slot at ``N`` for the actual key. Cycles
    are broken with a marker; depth is bounded to avoid runaways.
    """
    if depth > 30:
        return "<depth>"
    if not 0 <= idx < len(slots):
        return f"<idx{idx}>"
    if idx in seen:
        return f"<cycle{idx}>"
    val = slots[idx]
    seen2 = seen | {idx}
    if isinstance(val, dict):
        out: dict[str, Any] = {}
        for k, v in val.items():
            if isinstance(k, str) and k.startswith("_") and k[1:].lstrip("-").isdigit():
                kr = _resolve(slots, int(k[1:]), seen2, depth + 1)
                key = kr if isinstance(kr, str) else str(kr)
            else:
                key = k
            out[key] = _resolve(slots, v, seen2, depth + 1) if isinstance(v, int) else v
        return out
    if isinstance(val, list):
        return [_resolve(slots, x, seen2, depth + 1) if isinstance(x, int) else x for x in val]
    return val


def _decode_data_file(raw: bytes) -> dict[str, Any]:
    """Parse a Remix `.data` payload into the resolved root dict."""
    slots = json.loads(raw)
    return _resolve(slots, 0)


def _extract_type_enums(schema: Any) -> list[list[str]]:
    """Walk a JSON Schema looking for ``x-apidog-overrides.type.enum`` lists."""
    out: list[list[str]] = []

    def walk(o: Any) -> None:
        if isinstance(o, dict):
            ov = o.get("x-apidog-overrides")
            if isinstance(ov, dict):
                t = ov.get("type")
                if isinstance(t, dict) and "enum" in t:
                    out.append(list(t["enum"]))
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(schema)
    return out


def _normalize_endpoint(rd: dict[str, Any]) -> dict[str, Any]:
    """Pick the fields callers actually use; drop Apidog UI metadata."""
    rb = rd.get("requestBody") or {}
    request_examples = [
        ex.get("value", "") for ex in (rb.get("examples") or []) if isinstance(ex, dict)
    ]
    responses_out: list[dict[str, Any]] = []
    for resp in rd.get("responses") or []:
        if not isinstance(resp, dict):
            continue
        examples = [
            ex.get("data", "") for ex in (resp.get("responseExamples") or []) if isinstance(ex, dict)
        ]
        responses_out.append(
            {
                "code": str(resp.get("code", "")),
                "description": (resp.get("description") or "").strip(),
                "type_enums": _extract_type_enums(resp.get("jsonSchema") or {}),
                "examples": examples,
            }
        )
    return {
        "id": rd.get("id"),
        "name": rd.get("name", ""),
        "method": (rd.get("method") or "").upper(),
        "path": rd.get("path", ""),
        "status": rd.get("status", ""),
        "description": (rd.get("description") or "").strip(),
        "request": {
            "media_type": rb.get("mediaType") or rb.get("type") or "",
            "examples": request_examples,
        },
        "responses": responses_out,
    }


def fetch_endpoint(share_uuid: str, endpoint_id: int) -> dict[str, Any]:
    """Fetch + decode + normalize one endpoint from the share link."""
    url = f"{SHARE_HOST}/{share_uuid}/api-{endpoint_id}.data"
    raw = _http_get(url)
    resolved = _decode_data_file(raw)
    try:
        rd = resolved["root"]["data"]["docsDataState"]["resourceData"]["data"]
    except (KeyError, TypeError) as e:
        raise RuntimeError(f"unexpected share .data structure for {endpoint_id}: {e}")
    return _normalize_endpoint(rd)


_ID_PATH_RE = re.compile(
    rb',(\d{6,})\s*,\s*\\?"([^"\\]*)\\?"\s*,\s*\\?"apiDetail\.\1\\?"\s*,\s*\\?"(/[^"\\]*)\\?"'
)


def list_endpoints(share_uuid: str) -> list[dict[str, Any]]:
    """Enumerate (id, name, path) from the share index page.

    Parses the Remix stream embedded in <script> tags. The stream is
    JS-string-escaped (so ``"`` appears as ``\\"``), but forward slashes
    are not escaped. Order matches the HTML.
    """
    url = f"{SHARE_HOST}/{share_uuid}"
    raw = _http_get(url)
    seen: set[int] = set()
    out: list[dict[str, Any]] = []
    for m in _ID_PATH_RE.finditer(raw):
        eid = int(m.group(1))
        if eid in seen:
            continue
        seen.add(eid)
        name = m.group(2).decode("utf-8", "replace")
        path = m.group(3).decode("utf-8", "replace")
        out.append({"id": eid, "name": name, "path": path})
    return out


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="apidog-share-fetch", description=__doc__.split("\n\n")[0])
    p.add_argument("--share-uuid", required=True, help="UUID from share.apidog.com/<uuid>")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--endpoint-id", type=int, help="Fetch one endpoint by Apidog endpoint ID")
    g.add_argument("--path-prefix", help="Fetch all endpoints whose path starts with this prefix")
    g.add_argument("--list", action="store_true", help="List (id, method, name, path) only")
    p.add_argument(
        "--from-file",
        help=argparse.SUPPRESS,  # internal: read raw .data from local file (tests)
    )
    args = p.parse_args(argv)

    try:
        if args.from_file:
            # Test path: skip HTTP, read raw .data bytes from disk
            with open(args.from_file, "rb") as f:
                resolved = _decode_data_file(f.read())
            rd = resolved["root"]["data"]["docsDataState"]["resourceData"]["data"]
            json.dump(_normalize_endpoint(rd), sys.stdout, indent=2, ensure_ascii=False, sort_keys=True)
            sys.stdout.write("\n")
            return 0

        if args.list:
            entries = list_endpoints(args.share_uuid)
            json.dump(entries, sys.stdout, indent=2, ensure_ascii=False, sort_keys=True)
            sys.stdout.write("\n")
            return 0

        if args.endpoint_id is not None:
            ep = fetch_endpoint(args.share_uuid, args.endpoint_id)
            json.dump(ep, sys.stdout, indent=2, ensure_ascii=False, sort_keys=True)
            sys.stdout.write("\n")
            return 0

        if args.path_prefix:
            entries = list_endpoints(args.share_uuid)
            matched = [e for e in entries if e["path"].startswith(args.path_prefix)]
            results = [fetch_endpoint(args.share_uuid, e["id"]) for e in matched]
            json.dump(results, sys.stdout, indent=2, ensure_ascii=False, sort_keys=True)
            sys.stdout.write("\n")
            return 0

    except (urllib.error.URLError, RuntimeError) as e:
        print(f"apidog-share-fetch: {e}", file=sys.stderr)
        return 2

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
