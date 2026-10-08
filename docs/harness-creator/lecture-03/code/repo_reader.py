#!/usr/bin/env python3
"""
repo_reader.py — Score a repository's discoverability as a system of record.

Ported from learn-harness-engineering Lecture 03 (repo-reader.ts, MIT, WalkingLab).
Same 8 criteria and weights as the original, so scores stay comparable.

Usage: python3 repo_reader.py [path]   (defaults to the current directory)
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

# (name, max points, candidate paths, must be a directory)
CRITERIA: list[tuple[str, int, list[str], bool]] = [
    ("AGENTS.md / CLAUDE.md", 15, ["AGENTS.md", "CLAUDE.md", ".claude/CLAUDE.md"], False),
    ("Documentation directory", 10, ["docs", "documentation", "doc"], True),
    (
        "Architecture documentation",
        15,
        [
            "architecture.md",
            "ARCHITECTURE.md",
            "docs/architecture.md",
            "docs/architecture/",
            "design.md",
            "DESIGN.md",
        ],
        False,
    ),
    (
        "Feature tracking",
        15,
        [
            "feature_list.json",
            "features.md",
            "FEATURES.md",
            "docs/features.md",
            "tasks.json",
            "TODO.md",
        ],
        False,
    ),
    (
        "Handoff / session continuity",
        15,
        [
            "HANDOFF.md",
            "handoff.md",
            "SESSION_NOTES.md",
            "docs/handoff.md",
            ".handoff",
            "PROGRESS.md",
        ],
        False,
    ),
    ("Testing structure", 10, ["test", "tests", "__tests__", "spec"], True),
    (
        "Configuration files",
        10,
        ["package.json", "tsconfig.json", "pyproject.toml", "Cargo.toml", "go.mod"],
        False,
    ),
    ("README", 10, ["README.md", "README.rst", "README.txt", "README"], False),
]

MAX_SCORE = sum(points for _, points, _, _ in CRITERIA)

GRADES: list[tuple[int, str]] = [
    (90, "A -- Repository is a strong system of record"),
    (70, "B -- Good foundation, minor gaps"),
    (50, "C -- Partial structure, significant gaps"),
    (30, "D -- Minimal structure, hard for agents to navigate"),
    (0, "F -- Repository lacks discoverability signals"),
]


def grade(total: int) -> str:
    pct = total / MAX_SCORE * 100
    return next(label for floor, label in GRADES if pct >= floor)


def score_repo(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    total = 0
    for name, points, candidates, dirs_only in CRITERIA:
        found = [
            c for c in candidates if (root / c).is_dir() or (not dirs_only and (root / c).exists())
        ]
        earned = points if found else 0
        total += earned
        checks.append({"name": name, "points": earned, "max": points, "found": found})
    return {"total": total, "max": MAX_SCORE, "checks": checks}


def main(argv: list[str]) -> int:
    root = Path(argv[1] if len(argv) > 1 else ".").resolve()
    if not root.is_dir():
        print(f"Error: directory not found: {root}", file=sys.stderr)
        return 1
    result = score_repo(root)
    print(f"Target: {root}\n")
    for c in result["checks"]:
        status = "PASS" if c["points"] else "FAIL"
        detail = ", ".join(c["found"]) if c["found"] else "missing"
        print(f"| {c['name']:<30}| {c['points']}/{c['max']:<4}| {status:<5}| {detail}")
    pct = round(result["total"] / MAX_SCORE * 100)
    print(f"\nTOTAL SCORE: {result['total']} / {MAX_SCORE}  ({pct}%)")
    print(f"GRADE: {grade(result['total'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
