#!/usr/bin/env python3
"""One trend over all target repos: their audits and their verify-gate runs.

Audits are repo_audit.py --save files (docs/telemetry/repos/<repo>/<date>.json,
committed); verify runs are <runtime>/telemetry/<repo>/verify-runs-*.jsonl,
written per machine by verify-gate.sh. Prints a markdown table: first -> latest
audit in the window (the latest earlier one when none falls inside) and the
verify runs in the window.

Usage: repo_trend.py [--days N]
"""

from __future__ import annotations

import argparse
import datetime
import json
import statistics
import sys
from pathlib import Path
from typing import Any

HARNESS = Path(__file__).resolve().parent.parent


def _runtime_dir() -> Path:
    marker = HARNESS / ".skills-repo-id"
    name = marker.read_text().split()[0] if marker.is_file() else "agent-skills-setup"
    return Path.home() / f".{name}"


def _audits(root: Path, repo: str, start: datetime.date) -> list[tuple[str, dict[str, Any]]]:
    rows: list[tuple[str, dict[str, Any]]] = []
    for path in sorted((root / repo).glob("*.json")):
        try:
            rows.append((path.stem, json.loads(path.read_text(encoding="utf-8"))))
        except (OSError, ValueError):
            continue
    inside = [r for r in rows if r[0] >= start.isoformat()]
    return inside or rows[-1:]


def _metrics(audit: dict[str, Any]) -> dict[str, Any]:
    loaded = audit.get("always_loaded", {})
    return {
        "loaded": loaded.get("tokens"),
        "scoped": loaded.get("skill_tokens_scoped"),
        "state": sum(s.get("tokens") or 0 for s in audit.get("state_files", [])),
        "drifted": sum(1 for h in audit.get("hooks", []) if h.get("status") == "drifted"),
        "agents": ",".join(a for a, on in audit.get("agent_hooks", {}).items() if on) or "none",
    }


def _span(first: Any, last: Any) -> str:
    a, b = ("–" if v is None else v for v in (first, last))
    return f"{a}" if a == b else f"{a} → {b}"


def _runs(runtime: Path, repo: str, start: datetime.date) -> str:
    rows: list[dict[str, Any]] = []
    for path in sorted((runtime / "telemetry" / repo).glob("verify-runs-*.jsonl")):
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                row = json.loads(line)
                day = datetime.date.fromisoformat(str(row["ts"])[:10])
            except (ValueError, KeyError, TypeError):
                continue
            if day >= start:
                rows.append(row)
    if not rows:
        return "no verify runs"
    secs = [int(r.get("duration_s") or 0) for r in rows]
    failed = sum(1 for r in rows if r.get("result") != "pass")
    return (
        f"{len(rows)} runs, {failed} failed, "
        f"median {int(statistics.median(secs))}s, max {max(secs)}s"
    )


def render(audits: Path, runtime: Path, days: int, today: datetime.date | None = None) -> str:
    start = (today or datetime.datetime.now().astimezone().date()) - datetime.timedelta(days=days)
    repos = sorted(p.name for p in audits.iterdir() if p.is_dir()) if audits.is_dir() else []
    if not repos:
        return f"no repo audits under {audits}"
    out = [
        f"Since {start} ({days} days). Tokens are estimates (chars/4).",
        "",
        (
            "| repo | audits | always-loaded tok | scoped skills tok | state files tok "
            "| drifted hooks | agents with hooks | verify runs |"
        ),
        "|---|---|---|---|---|---|---|---|",
    ]
    for repo in repos:
        rows = _audits(audits, repo, start)
        if not rows:
            continue
        first, last = _metrics(rows[0][1]), _metrics(rows[-1][1])
        dates = _span(rows[0][0], rows[-1][0])
        cells = [
            _span(first[k], last[k]) for k in ("loaded", "scoped", "state", "drifted", "agents")
        ]
        out.append(
            f"| {repo} | {dates} | " + " | ".join(cells) + f" | {_runs(runtime, repo, start)} |"
        )
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--audits", type=Path, default=HARNESS / "docs/telemetry/repos")
    ap.add_argument("--runtime", type=Path, default=None)
    args = ap.parse_args(argv)
    print(render(args.audits, args.runtime or _runtime_dir(), days=args.days))
    return 0


if __name__ == "__main__":
    sys.exit(main())
