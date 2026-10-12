#!/usr/bin/env python3
"""Print the current work from feature_list.json and PROGRESS.md in a few lines.

Usage: state_brief.py [repo_dir]
Exit 0 on success; exit 2 when a state file is missing or unreadable.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

ACTIVE_STATUSES = ("active", "in_progress", "doing")
DONE_STATUSES = ("done", "completed")
QUEUE_ITEM_RE = re.compile(r"^\d+\.\s+\*\*(.+?)\*\*(?:\s|$)")
MAX_IN_PROGRESS = 5
MAX_ACTIVE = 3
MAX_QUEUE = 8
MAX_LINE = 160


class StateMissing(Exception):
    pass


def _clip(text: object) -> str:
    s = " ".join(str(text).split())
    return s if len(s) <= MAX_LINE else s[: MAX_LINE - 1] + "…"


def _features(repo: Path) -> list[dict[str, Any]]:
    path = repo / "feature_list.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, RecursionError) as e:
        raise StateMissing(f"cannot read {path}: {e}") from e
    items = data.get("features", data) if isinstance(data, dict) else data
    if not isinstance(items, list):
        raise StateMissing(f"{path}: root or 'features' must be a list")
    return [f for f in items if isinstance(f, dict)]


def _section(lines: list[str], heading: str) -> list[str]:
    """Lines under a `### heading`, up to the next heading."""
    out: list[str] = []
    inside = False
    for line in lines:
        if line.startswith("#"):
            inside = line.lstrip("#").strip() == heading
            continue
        if inside:
            out.append(line)
    return out


def _queue_titles(next_lines: list[str]) -> list[str]:
    titles: list[str] = []
    for line in next_lines:
        if line.startswith("**Pending Owner"):
            break
        m = QUEUE_ITEM_RE.match(line)
        if m and not m.group(1).startswith("[DONE"):
            titles.append(m.group(1))
    return titles


def brief(repo: Path) -> str:
    features = _features(repo)
    progress = repo / "PROGRESS.md"
    try:
        lines = progress.read_text(encoding="utf-8").splitlines()
    except (OSError, ValueError) as e:
        raise StateMissing(f"cannot read {progress}: {e}") from e

    out: list[str] = []
    active = [f for f in features if f.get("status") in ACTIVE_STATUSES]
    if active:
        for f in active[:MAX_ACTIVE]:
            out.append(_clip(f"Active: {f.get('id')} {f.get('name', '')}"))
            verification = f.get("verification") or f.get("acceptance_criteria")
            if verification:
                out.append(f"  Verify: {_clip(verification)}")
        if len(active) > MAX_ACTIVE:
            out.append(f"  ... {len(active) - MAX_ACTIVE} more active in feature_list.json")
    else:
        out.append("Active: none")
        done = [f for f in features if f.get("status") in DONE_STATUSES]
        if done:
            out.append(_clip(f"Last completed: {done[-1].get('id')} {done[-1].get('name', '')}"))

    in_progress = [ln.strip() for ln in _section(lines, "What's In Progress") if ln.strip()]
    if in_progress:
        out.append("In progress:")
        out.extend(f"  {_clip(ln)}" for ln in in_progress[:MAX_IN_PROGRESS])
        if len(in_progress) > MAX_IN_PROGRESS:
            out.append(f"  ... {len(in_progress) - MAX_IN_PROGRESS} more in PROGRESS.md")

    queue = _queue_titles(_section(lines, "What's Next"))
    if queue:
        out.append("Next:")
        out.extend(f"  {i}. {_clip(t)}" for i, t in enumerate(queue[:MAX_QUEUE], 1))
        if len(queue) > MAX_QUEUE:
            out.append(f"  ... {len(queue) - MAX_QUEUE} more in PROGRESS.md")
    if not in_progress and not queue:
        out.append("PROGRESS.md has no In Progress or Next section")
    return "\n".join(out)


def main(argv: list[str]) -> int:
    repo = Path(argv[0]) if argv else Path(__file__).resolve().parent.parent
    try:
        print(brief(repo))
    except StateMissing as e:
        print(f"state_brief: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
