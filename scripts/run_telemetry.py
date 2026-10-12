#!/usr/bin/env python3
"""Read-only run telemetry collector for Claude Code session traces.

Reads one session transcript (and its subagents/ directory) and writes one JSON
record per run. Every metric is {value, source, status} with status measured,
estimated or missing; an unavailable metric is never reported as zero.
See docs/stories/run-telemetry/spec.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

TOKEN_FIELDS = {
    "input_tokens_sum": "input_tokens",
    "output_tokens_sum": "output_tokens",
    "cache_read_sum": "cache_read_input_tokens",
    "cache_creation_sum": "cache_creation_input_tokens",
}


def parse_ts(value: str) -> datetime:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def metric(
    value: Any, source: str, status: str = "measured", note: str | None = None
) -> dict[str, Any]:
    m: dict[str, Any] = {"value": value, "source": source, "status": status}
    if note:
        m["note"] = note
    return m


def missing(source: str, note: str | None = None) -> dict[str, Any]:
    return metric(None, source, "missing", note)


def _read_rows(path: Path) -> tuple[list[dict[str, Any]], int]:
    rows: list[dict[str, Any]] = []
    bad = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                r = json.loads(line)
            except ValueError:
                bad += 1
                continue
            if isinstance(r, dict):
                rows.append(r)
            else:
                bad += 1
    return rows, bad


def _in_window(row: dict[str, Any], start: datetime | None, end: datetime | None) -> bool:
    if start is None and end is None:
        return True
    ts = row.get("timestamp")
    if not isinstance(ts, str):
        return False
    try:
        t = parse_ts(ts)
    except ValueError:
        return False
    return (start is None or t >= start) and (end is None or t <= end)


def _usage_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    for r in rows:
        m = r.get("message")
        if isinstance(m, dict) and isinstance(m.get("usage"), dict):
            out.append(r)
    return out


def _row_numbers(usage: dict[str, Any]) -> dict[str, int | None]:
    return {
        "input_tokens": usage.get("input_tokens"),
        "output_tokens": usage.get("output_tokens"),
        "cache_read_input_tokens": usage.get("cache_read_input_tokens"),
        "cache_creation_input_tokens": usage.get("cache_creation_input_tokens"),
    }


def _scope_usage(rows: list[dict[str, Any]], source: str) -> dict[str, Any]:
    """Deduplicate usage rows by message id within one scope and sum tokens."""
    urows = _usage_rows(rows)
    by_id: dict[str, list[dict[str, Any]]] = {}
    order: list[str] = []
    no_id: list[dict[str, Any]] = []
    for r in urows:
        mid = r["message"].get("id")
        if not isinstance(mid, str) or not mid:
            no_id.append(r)
            continue
        if mid not in by_id:
            by_id[mid] = []
            order.append(mid)
        by_id[mid].append(r)

    chosen: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []
    for mid in order:
        group = by_id[mid]
        nums = [_row_numbers(g["message"]["usage"]) for g in group]
        if all(n == nums[0] for n in nums):
            chosen.append(group[0])
            continue
        best = max(group, key=lambda g: g["message"]["usage"].get("output_tokens") or 0)
        chosen.append(best)
        conflicts.append({"message_id": mid, "raw_rows": nums})
    chosen.extend(no_id)

    tokens: dict[str, Any] = {}
    for name, field in TOKEN_FIELDS.items():
        vals = [c["message"]["usage"].get(field) for c in chosen]
        present = [v for v in vals if isinstance(v, int)]
        if not present:
            tokens[name] = missing(source, f"no usage row carried {field}")
            continue
        total = sum(present)
        note = None
        if name == "input_tokens_sum":
            note = "sums the context re-sent on every turn, so it is not unique content and not billed usage"
        elif name in ("cache_read_sum", "cache_creation_sum") and total == 0:
            note = (
                "every row reports 0; cannot tell no caching from a gateway that does not report it"
            )
        tokens[name] = metric(total, source, note=note)
    ins = [c["message"]["usage"].get("input_tokens") for c in chosen]
    outs = [c["message"]["usage"].get("output_tokens") for c in chosen]
    last_in = next((v for v in reversed(ins) if isinstance(v, int)), None)
    out_sum = sum(v for v in outs if isinstance(v, int))
    if last_in is None:
        tokens["last_context_tokens"] = missing(source)
        tokens["reported_context_total"] = missing(source)
    else:
        tokens["last_context_tokens"] = metric(
            last_in, source, note="input tokens of the final turn: context size, not usage"
        )
        tokens["reported_context_total"] = metric(
            last_in + out_sum,
            source,
            note="final-turn input + summed output; this is the figure the harness reports for subagents, not billed usage",
        )
    models: list[str] = []
    for c in chosen:
        mdl = c["message"].get("model")
        if isinstance(mdl, str) and mdl not in models:
            models.append(mdl)
    return {
        "tokens": tokens,
        "usage_rows": len(urows),
        "distinct_message_ids": len(order),
        "rows_without_message_id": len(no_id),
        "conflicts": conflicts,
        "models": models,
    }


def _span_ms(rows: list[dict[str, Any]]) -> int | None:
    times: list[datetime] = []
    for r in rows:
        ts = r.get("timestamp")
        if isinstance(ts, str):
            try:
                times.append(parse_ts(ts))
            except ValueError:
                continue
    if len(times) < 2:
        return None
    return int((max(times) - min(times)).total_seconds() * 1000)


def _turn_time(rows: list[dict[str, Any]]) -> dict[str, Any]:
    vals = [
        r["durationMs"]
        for r in rows
        if r.get("type") == "system"
        and r.get("subtype") == "turn_duration"
        and isinstance(r.get("durationMs"), (int, float))
    ]
    if not vals:
        return missing("no turn_duration records")
    return metric(
        int(sum(vals)),
        "system turn_duration records",
        note="time inside turns, excluding idle gaps",
    )


def _spawn_ids(rows: list[dict[str, Any]]) -> list[str]:
    ids: list[str] = []
    for r in rows:
        m = r.get("message")
        content = m.get("content") if isinstance(m, dict) else None
        if not isinstance(content, list):
            continue
        for b in content:
            if (
                isinstance(b, dict)
                and b.get("type") == "tool_use"
                and b.get("name") in ("Agent", "Task")
            ):
                if isinstance(b.get("id"), str):
                    ids.append(b["id"])
    return ids


def _event_counts(rows: list[dict[str, Any]]) -> dict[str, Any]:
    compactions = sum(
        1 for r in rows if r.get("type") == "system" and r.get("subtype") == "compact_boundary"
    )
    api_errors = sum(1 for r in rows if r.get("isApiErrorMessage") is True)
    return {
        "context_compactions": metric(compactions, "system compact_boundary records"),
        "api_errors": metric(api_errors, "records with isApiErrorMessage"),
        "retries": missing("no structured retry record in session files"),
        "timeouts": missing("no structured timeout record in session files"),
    }


def _subagents(
    session_dir: Path, session_id: str, start: datetime | None, end: datetime | None
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    sub_dir = session_dir / session_id / "subagents"
    if not sub_dir.is_dir():
        return out
    for path in sorted(sub_dir.glob("agent-*.jsonl")):
        agent_id = path.stem[len("agent-") :]
        rows, bad = _read_rows(path)
        rows = [r for r in rows if _in_window(r, start, end)]
        if not rows:
            continue
        meta: dict[str, Any] = {}
        meta_path = path.with_suffix(".meta.json")
        if meta_path.is_file():
            try:
                loaded = json.loads(meta_path.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    meta = loaded
            except ValueError:
                pass
        scope = _scope_usage(rows, "subagent usage rows")
        dur = _span_ms(rows)
        out.append(
            {
                "agent_id": agent_id,
                "parent_session_id": session_id,
                "tool_use_id": meta.get("toolUseId"),
                "agent_type": meta.get("agentType"),
                "description": meta.get("description"),
                "model": metric(scope["models"], "assistant message")
                if scope["models"]
                else missing("assistant message"),
                "duration_ms": metric(dur, "first to last record timestamp")
                if dur is not None
                else missing("transcript timestamps"),
                "outcome": missing("no structured outcome record; notification text is not parsed"),
                "tokens": scope["tokens"],
                "usage_rows": scope["usage_rows"],
                "distinct_message_ids": scope["distinct_message_ids"],
                "conflicts": scope["conflicts"],
                "malformed_lines": bad,
            }
        )
    return out


def _outside_agent(
    log: Path | None, start: datetime | None, end: datetime | None
) -> dict[str, Any]:
    if log is None or not log.is_file():
        return {"attempts_logged": missing("outside-agent-runs.jsonl not found")}
    attempts = 0
    legacy = 0
    results: Counter[str] = Counter()
    for r in _read_rows(log)[0]:
        if not _in_window(r, start, end):
            continue
        if r.get("attempt") is True:
            attempts += 1
            results[str(r.get("result"))] += 1
        else:
            legacy += 1
    return {
        "attempts_logged": metric(attempts, "outside-agent-runs.jsonl attempt rows"),
        "results": dict(results),
        "legacy_success_only_rows": metric(
            legacy,
            "outside-agent-runs.jsonl rows without attempt=true",
            note="written before attempt logging existed: failures were not logged, so attempts are undercounted for this period",
        ),
    }


def _gates(report: Path | None) -> dict[str, Any]:
    if report is None or not report.is_file():
        return missing("no harness-verify --report file given")
    try:
        data = json.loads(report.read_text(encoding="utf-8"))
    except ValueError:
        return missing("harness-verify report is not valid JSON")
    return metric(
        {
            "status": data.get("status"),
            "total_duration_ms": data.get("total_duration_ms"),
            "gates": data.get("gates"),
            "failed": data.get("failed"),
        },
        "harness-verify --report",
    )


def collect_run(
    session_file: Path,
    *,
    start: str | None = None,
    end: str | None = None,
    verify_report: Path | None = None,
    outside_log: Path | None = None,
) -> dict[str, Any]:
    t_start = parse_ts(start) if start else None
    t_end = parse_ts(end) if end else None
    session_id = session_file.stem
    all_rows, bad = _read_rows(session_file)
    rows = [r for r in all_rows if _in_window(r, t_start, t_end)]

    parent = _scope_usage(rows, "session usage rows")
    parent["malformed_lines"] = bad
    subs = _subagents(session_file.parent, session_id, t_start, t_end)

    spawns = _spawn_ids(rows)
    matched = {s["tool_use_id"] for s in subs}
    wall = _span_ms(rows)
    agent_ms = [s["duration_ms"]["value"] for s in subs if s["duration_ms"]["value"] is not None]

    key = f"{session_id}|{start or ''}|{end or ''}"
    run_id = f"{session_id[:8]}-{hashlib.sha256(key.encode()).hexdigest()[:10]}"
    return {
        "run_id": run_id,
        "schema_version": 1,
        "session_id": session_id,
        "window": {"start": start, "end": end},
        "wall_time_ms": metric(
            wall,
            "first to last parent timestamp",
            note="includes idle time between prompts",
        )
        if wall is not None
        else missing("parent timestamps"),
        "active_turn_time_ms": _turn_time(rows),
        "agent_time_ms": (
            metric(
                sum(agent_ms),
                "sum of subagent transcript spans",
                note="can exceed wall time because subagents run in parallel; not a duration of the run",
            )
            if agent_ms
            else missing("no subagent with timestamps")
        ),
        "parent": parent,
        "subagents": subs,
        "subagent_count": metric(len(subs), "subagents/agent-*.jsonl"),
        "spawn_calls": metric(len(spawns), "Agent tool_use blocks in the parent"),
        "unmatched_spawns": [s for s in spawns if s not in matched],
        "events": _event_counts(rows),
        "outside_agent": _outside_agent(outside_log, t_start, t_end),
        "gates": _gates(verify_report),
        "cost_usd": missing(
            "none",
            "no authoritative cost source; custom ANTHROPIC_BASE_URL makes public pricing a guess, so it is not estimated",
        ),
        "human_corrections": missing("no reliable automatic source"),
        "rework": missing("no reliable automatic source"),
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Collect run telemetry from a Claude Code session file."
    )
    ap.add_argument("--session", required=True, type=Path, help="session transcript .jsonl")
    ap.add_argument("--start", help="window start (ISO timestamp)")
    ap.add_argument("--end", help="window end (ISO timestamp)")
    ap.add_argument("--verify-report", type=Path, help="harness-verify.sh --report JSON")
    ap.add_argument("--outside-log", type=Path, help="outside-agent-runs.jsonl")
    ap.add_argument("--out-dir", type=Path, default=Path("docs/telemetry/runs"))
    args = ap.parse_args(argv)
    if not args.session.is_file():
        print(f"run_telemetry: session file not found: {args.session}", file=sys.stderr)
        return 2
    try:
        run = collect_run(
            args.session,
            start=args.start,
            end=args.end,
            verify_report=args.verify_report,
            outside_log=args.outside_log,
        )
    except ValueError as e:
        print(f"run_telemetry: bad timestamp: {e}", file=sys.stderr)
        return 2
    args.out_dir.mkdir(parents=True, exist_ok=True)
    out = args.out_dir / f"{run['run_id']}.json"
    out.write_text(json.dumps(run, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
