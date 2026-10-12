#!/usr/bin/env python3
"""Compare run telemetry records (docs/telemetry/runs/*.json) in one table.

Reads the JSON files written by scripts/run_telemetry.py. A metric whose status
is missing prints as "n/a"; it is never shown as 0. See docs/stories/run-telemetry/spec.md.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

NA = "n/a"


def _val(m: Any) -> Any:
    if isinstance(m, dict) and m.get("status") != "missing":
        return m.get("value")
    return None


def _fmt_int(v: Any) -> str:
    return NA if v is None else f"{int(v):,}"


def _fmt_ms(v: Any) -> str:
    if v is None:
        return NA
    s = float(v) / 1000
    if s < 60:
        return f"{s:.0f}s"
    if s < 3600:
        return f"{s / 60:.1f}m"
    return f"{s / 3600:.1f}h"


def load_runs(runs_dir: Path) -> list[dict[str, Any]]:
    runs: list[dict[str, Any]] = []
    for p in sorted(runs_dir.glob("*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict) and "run_id" in data:
            runs.append(data)
    return runs


def row(run: dict[str, Any]) -> dict[str, str]:
    parent = run.get("parent", {})
    tokens = parent.get("tokens", {})
    subs = run.get("subagents", [])
    sub_out = [_val(s.get("tokens", {}).get("output_tokens_sum")) for s in subs]
    known = [v for v in sub_out if v is not None]
    gates = _val(run.get("gates"))
    return {
        "run": str(run.get("run_id", "?")),
        "out_tok": _fmt_int(_val(tokens.get("output_tokens_sum"))),
        "ctx_tok": _fmt_int(_val(tokens.get("last_context_tokens"))),
        "wall": _fmt_ms(_val(run.get("wall_time_ms"))),
        "turns": _fmt_ms(_val(run.get("active_turn_time_ms"))),
        "subs": str(
            _val(run.get("subagent_count")) if _val(run.get("subagent_count")) is not None else NA
        ),
        "sub_out_tok": _fmt_int(sum(known)) if known and len(known) == len(sub_out) else NA,
        "unattributed": str(len(run.get("subagents_without_spawn", []))),
        "conflicts": str(len(parent.get("conflicts", []))),
        "gates": NA if gates is None else str(gates.get("status")),
    }


COLUMNS = [
    "run",
    "out_tok",
    "ctx_tok",
    "wall",
    "turns",
    "subs",
    "sub_out_tok",
    "unattributed",
    "conflicts",
    "gates",
]


def render(runs: list[dict[str, Any]]) -> str:
    rows = [row(r) for r in runs]
    widths = {c: max(len(c), *(len(r[c]) for r in rows)) if rows else len(c) for c in COLUMNS}
    lines = ["  ".join(c.ljust(widths[c]) for c in COLUMNS)]
    lines.append("  ".join("-" * widths[c] for c in COLUMNS))
    lines.extend("  ".join(r[c].ljust(widths[c]) for c in COLUMNS) for r in rows)
    lines.append("")
    lines.append(
        "n/a = missing, not zero. out_tok = deduplicated output tokens. ctx_tok = final-turn context size, not usage. "
        "wall includes idle time; turns = time inside turns. unattributed = subagents with no parent spawn call."
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Compare run telemetry records.")
    ap.add_argument("--runs-dir", type=Path, default=Path("docs/telemetry/runs"))
    ap.add_argument("--json", action="store_true", help="emit the table rows as JSON")
    args = ap.parse_args(argv)
    if not args.runs_dir.is_dir():
        print(f"run_report: no such directory: {args.runs_dir}", file=sys.stderr)
        return 2
    runs = load_runs(args.runs_dir)
    if not runs:
        print(f"run_report: no run records in {args.runs_dir}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps([row(r) for r in runs], indent=2))
    else:
        print(render(runs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
