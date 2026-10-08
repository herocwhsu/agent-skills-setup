#!/usr/bin/env python3
"""
feature_list_validator.py — Validate feature_list.json and flag unevidenced "done" entries.

Ported from learn-harness-engineering Lecture 08 (feature-list-validator.ts, MIT, WalkingLab),
adapted to this repo's schema: {"features": [...]} with id/name/description/status/evidence.
The original's `passes: true` + `verification[]` maps to `status: "done"` + `evidence`.

Usage: python3 feature_list_validator.py [path-to-feature_list.json-or-its-directory]
Exit 0 = valid, 1 = schema errors or done-without-evidence, 2 = file unreadable.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

REQUIRED_FIELDS = ("id", "name", "description", "status")


def has_text(value: Any) -> bool:
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (list, tuple)):
        return any(has_text(v) for v in value)
    if isinstance(value, dict):
        return any(has_text(v) for v in value.values())
    return False


def load_features(path: Path) -> list[Any]:
    if path.is_dir():
        path = path / "feature_list.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    features = data.get("features") if isinstance(data, dict) else data
    if not isinstance(features, list):
        raise ValueError(f"{path}: expected a list or an object with a 'features' list")
    return features


def validate(features: list[Any]) -> dict[str, Any]:
    errors: list[str] = []
    done_without_evidence: list[str] = []
    seen: set[str] = set()

    for index, entry in enumerate(features):
        if not isinstance(entry, dict):
            errors.append(f"entry {index + 1}: must be an object")
            continue
        label = str(entry.get("id") or f"entry {index + 1}")
        for field in REQUIRED_FIELDS:
            value = entry.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"[{label}] missing or invalid '{field}'")
        fid = entry.get("id")
        if isinstance(fid, str):
            if fid in seen:
                errors.append(f"[{label}] duplicate id")
            seen.add(fid)
        if entry.get("status") == "done" and not has_text(entry.get("evidence")):
            done_without_evidence.append(label)

    return {
        "is_valid": not errors and not done_without_evidence,
        "errors": errors,
        "done_without_evidence": done_without_evidence,
        "total": len(features),
    }


def main(argv: list[str]) -> int:
    path = Path(argv[1] if len(argv) > 1 else "feature_list.json")
    try:
        report = validate(load_features(path))
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    for err in report["errors"]:
        print(f"SCHEMA: {err}")
    for fid in report["done_without_evidence"]:
        print(f"FLAGGED: {fid} is done without evidence")
    status = "valid" if report["is_valid"] else "INVALID"
    print(f"{report['total']} features, {status}")
    return 0 if report["is_valid"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
