#!/usr/bin/env python3
"""Validate feature_list.json for harness/guards/state-layer-guard.sh.

Usage: state_layer_check.py <feature_list.json> [<changed files, one per line>]
Exit 0 allows; exit 2 blocks and prints the reason to stderr.
"""

from __future__ import annotations

import fnmatch
import json
import sys
from pathlib import Path
from typing import Any

ACTIVE_STATUSES = ("active", "in_progress", "doing")

HEADERS = {
    "JSON": "Blocked: feature_list.json is not valid JSON:",
    "SCHEMA": "Blocked: feature_list.json schema violation:",
    "ARCHIVE": "Blocked: state layer archive reference error:",
    "WIP": "Blocked by WIP limit: feature_list.json has multiple active features:",
    "EXCLUSION": "Blocked: active feature scope exclusion violated:",
    "DONE": "Blocked: done feature lacks completion evidence:",
    "EVIDENCE": "Blocked: active feature lacks completion evidence:",
}
FOOTERS = {
    "ARCHIVE": (
        "WHY: feature_list.json references an archive file that is missing, invalid, or violates schema.",
        "FIX: Ensure all files in 'archive_references' exist and contain valid JSON features.",
    ),
    "EXCLUSION": (
        "WHY: Sprint contract in feature_list.json explicitly excluded this path to prevent scope creep.",
        "FIX: Revert changes to excluded file, or update feature exclusions if scope expansion was authorized.",
    ),
}


class StateLayerError(Exception):
    def __init__(self, kind: str, message: str) -> None:
        super().__init__(message)
        self.kind = kind
        self.message = message


def _load_json(path: Path) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _feature_list(data: Any) -> Any:
    return data.get("features", data) if isinstance(data, dict) else data


def has_text(v: Any) -> bool:
    if isinstance(v, str):
        return bool(v.strip())
    if isinstance(v, (list, tuple)):
        return any(has_text(x) for x in v)
    if isinstance(v, dict):
        return any(has_text(x) for x in v.values())
    return False


def _archived_features(data: Any, repo_root: Path) -> list[Any]:
    if not (isinstance(data, dict) and "archive_references" in data):
        return []
    refs = data["archive_references"]
    if not isinstance(refs, list) or not all(isinstance(r, str) and r.strip() for r in refs):
        raise StateLayerError(
            "ARCHIVE", "'archive_references' must be a list of non-empty string file paths."
        )
    archived: list[Any] = []
    for ref in refs:
        ref_path = (repo_root / ref).resolve()
        if not ref_path.is_file():
            raise StateLayerError("ARCHIVE", f"Referenced archive file does not exist: '{ref}'.")
        try:
            ref_data = _load_json(ref_path)
        except Exception as e:
            raise StateLayerError("ARCHIVE", f"Archive file '{ref}' is not valid JSON: {e}.") from e
        ref_feats = _feature_list(ref_data)
        if not isinstance(ref_feats, list):
            raise StateLayerError(
                "ARCHIVE", f"Archive file '{ref}' must contain a list of features."
            )
        archived.extend(ref_feats)
    return archived


def check(feature_file: Path, changed_files: list[str]) -> None:
    try:
        data = _load_json(feature_file)
    except Exception as e:
        raise StateLayerError("JSON", str(e)) from e

    features = _feature_list(data)
    if not isinstance(features, list):
        raise StateLayerError("SCHEMA", "feature_list root or 'features' must be a list")

    archived = _archived_features(data, feature_file.resolve().parent)

    for f in features:
        if isinstance(f, dict) and "exclusions" in f:
            ex = f.get("exclusions")
            if not isinstance(ex, list) or not all(isinstance(x, str) for x in ex):
                raise StateLayerError(
                    "SCHEMA", f"'exclusions' in feature '{f.get('id')}' must be a list of strings."
                )

    active = [f for f in features if isinstance(f, dict) and f.get("status") in ACTIVE_STATUSES]
    if len(active) > 1:
        ids = [f.get("id", "unknown") for f in active]
        raise StateLayerError(
            "WIP",
            f"WIP limit violation: {len(active)} features active concurrently: {ids}. Lecture 07 mandates WIP=1.",
        )

    for f in active:
        fid = f.get("id", "unknown")
        v = f.get("verification") or f.get("acceptance_criteria")
        if not v or not str(v).strip():
            raise StateLayerError(
                "EVIDENCE",
                f"Completion evidence missing: active feature '{fid}' has no non-empty "
                "'verification' or 'acceptance_criteria' command.",
            )
        for pattern in f.get("exclusions") or []:
            pat = pattern.strip()
            if not pat:
                continue
            for cf in changed_files:
                if fnmatch.fnmatch(cf, pat) or fnmatch.fnmatch(cf, f"*/{pat}"):
                    raise StateLayerError(
                        "EXCLUSION",
                        f"File '{cf}' modified in violation of exclusion pattern '{pat}' for active feature '{fid}'.",
                    )

    unevidenced = [
        f.get("id", "unknown")
        for f in features + archived
        if isinstance(f, dict) and f.get("status") == "done" and not has_text(f.get("evidence"))
    ]
    if unevidenced:
        raise StateLayerError("DONE", f"done features without 'evidence': {unevidenced}.")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: state_layer_check.py <feature_list.json> [changed files]", file=sys.stderr)
        return 2
    changed = [
        line.strip() for line in (argv[2] if len(argv) > 2 else "").splitlines() if line.strip()
    ]
    try:
        check(Path(argv[1]), changed)
    except StateLayerError as e:
        print(HEADERS[e.kind], file=sys.stderr)
        print(e.message, file=sys.stderr)
        for line in FOOTERS.get(e.kind, ()):
            print(line, file=sys.stderr)
        return 2
    except Exception as e:
        print("Blocked: state layer validation error:", file=sys.stderr)
        print(e, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
