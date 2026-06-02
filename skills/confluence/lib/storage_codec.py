#!/usr/bin/env python3
"""
storage_codec.py — XHTML storage <-> markdown + meta.json round-trip.

STATUS: stub. Decode/encode raise NotImplementedError until real-page
fixtures from the target Confluence instance are added under
tests/fixtures/.

Usage:
    python3 storage_codec.py decode --input page.json \
                                    --out-md page.md \
                                    --out-meta page.meta.json

    python3 storage_codec.py encode --md-file page.md \
                                    --meta-file page.meta.json \
                                    --out storage.xhtml

The decoder reads either a Confluence REST response JSON
(body.storage.value) or a raw .xml file. The encoder produces an XHTML
string suitable for body.storage.value on push.

See ../charter.md for round-trip integrity rules.
"""
from __future__ import annotations

import argparse
import sys


def decode(*, input_path: str, out_md: str, out_meta: str) -> None:
    raise NotImplementedError(
        "storage_codec.decode not yet implemented. "
        "Add fixtures to tests/fixtures/ and implement per the plan in "
        "docs/superpowers/plans/2026-06-02-confluence-skill.md (Task 1)."
    )


def encode(*, md_file: str, meta_file: str, out: str) -> None:
    raise NotImplementedError(
        "storage_codec.encode not yet implemented. "
        "Depends on decode shape. See plan Task 2."
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_decode = sub.add_parser("decode")
    p_decode.add_argument("--input", required=True, help="REST response JSON or raw .xml file")
    p_decode.add_argument("--out-md", required=True)
    p_decode.add_argument("--out-meta", required=True)

    p_encode = sub.add_parser("encode")
    p_encode.add_argument("--md-file", required=True)
    p_encode.add_argument("--meta-file", required=True)
    p_encode.add_argument("--out", required=True)

    args = parser.parse_args(argv)

    try:
        if args.cmd == "decode":
            decode(input_path=args.input, out_md=args.out_md, out_meta=args.out_meta)
        else:
            encode(md_file=args.md_file, meta_file=args.meta_file, out=args.out)
    except NotImplementedError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
