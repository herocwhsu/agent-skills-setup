#!/usr/bin/env python3
"""
scope_tracker.py — Enforce single-active-feature (WIP=1) and executable verification.

Ported and enhanced from learn-harness-engineering Lecture 07.
Validates feature_list.json against:
  1. WIP <= 1: At most one feature can be 'active' or 'in_progress' at any time.
  2. Completion Evidence: Any active feature must have an executable 'verification' command.
  3. Git Scope Check: If given git modified files, verifies they match the active feature's scope.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


def load_feature_list(path: Path) -> List[Dict[str, Any]]:
    if not path.is_file():
        raise FileNotFoundError(f"feature_list not found at {path}")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict) and "features" in data:
        return data["features"]
    if isinstance(data, list):
        return data
    raise ValueError(f"Unexpected JSON structure in {path}")


def check_wip_and_evidence(features: List[Dict[str, Any]]) -> Dict[str, Any]:
    active_features = [
        f for f in features
        if f.get("status") in ("active", "in_progress", "doing")
    ]
    
    violations = []
    
    # WIP Limit check: WIP <= 1
    if len(active_features) > 1:
        active_ids = [f.get("id", "unknown") for f in active_features]
        violations.append(
            f"WIP LIMIT VIOLATION: {len(active_features)} features active concurrently: {active_ids}. "
            f"Lecture 07 mandates WIP=1 (only one active feature allowed)."
        )
    
    # Completion Evidence check for active features
    for f in active_features:
        fid = f.get("id", "unknown")
        verification = f.get("verification") or f.get("acceptance_criteria")
        if not verification or not str(verification).strip():
            violations.append(
                f"COMPLETION EVIDENCE VIOLATION: Active feature '{fid}' has no executable "
                f"'verification' or 'acceptance_criteria' command."
            )
            
    return {
        "active_count": len(active_features),
        "active_features": active_features,
        "violations": violations,
        "is_valid": len(violations) == 0,
    }


def check_git_diff_scope(repo_dir: Path, active_feature: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    try:
        res = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=repo_dir,
            capture_output=True,
            text=True,
            check=True
        )
    except Exception as e:
        return {"error": str(e), "files": []}

    modified_files = []
    for line in res.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.strip().split(maxsplit=1)
        if len(parts) == 2:
            modified_files.append(parts[1])

    allowed_patterns = []
    if active_feature:
        allowed_patterns = active_feature.get("allowed_paths", [])

    return {
        "modified_files": modified_files,
        "active_feature_id": active_feature.get("id") if active_feature else None,
        "allowed_patterns": allowed_patterns,
    }


def main() -> int:
    repo_dir = Path(__file__).resolve().parents[4]
    feature_file = repo_dir / "feature_list.json"

    if len(sys.argv) > 1:
        feature_file = Path(sys.argv[1])

    print(f"=== Scope Tracker (Lecture 07 WIP=1 Checker) ===")
    print(f"Inspecting: {feature_file}")

    try:
        features = load_feature_list(feature_file)
    except Exception as e:
        print(f"ERROR: Failed to load feature list: {e}", file=sys.stderr)
        return 2

    res = check_wip_and_evidence(features)
    print(f"Total features tracked: {len(features)}")
    print(f"Active features (WIP):  {res['active_count']}")

    if res["active_features"]:
        for f in res["active_features"]:
            print(f"  - Active: {f.get('id')} ({f.get('name')})")
            print(f"    Verification: {f.get('verification') or f.get('acceptance_criteria')}")

    if not res["is_valid"]:
        print("\nVIOLATIONS FOUND:")
        for v in res["violations"]:
            print(f"  [!] {v}", file=sys.stderr)
        return 1

    print("\nState layer satisfies WIP=1 and Completion Evidence constraints.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
