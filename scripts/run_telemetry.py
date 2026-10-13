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
import math
import os
import re
import sys
import unicodedata
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


_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)
_TOOL_USE_RE = re.compile(r"^toolu_[A-Za-z0-9_]{1,60}$")
_OPAQUE_ID_RE = re.compile(r"^[A-Za-z0-9]{1,40}$")
_SECRET_WORDS = re.compile(
    r"(api[-_ ]?key|passw(or)?d|pwd|secret|bearer|authorization|credential)", re.I
)
_TOKEN_ASSIGNMENT = re.compile(r"\btokens?\s*[=:]\s*(?=\S*[A-Za-z0-9])\S{8,}", re.I)
_SENSITIVE_SEGMENT = re.compile(
    r"^\.?(secrets?|credentials?|keys?|private|tokens?|passw(or)?d|ssh|aws|env|gnupg)$", re.I
)
_CREDENTIAL_SHAPES = re.compile(
    r"((?<![A-Za-z0-9])sk[-_][A-Za-z0-9_-]{6,}|gh[pousr]_[A-Za-z0-9]{8,}|AKIA[0-9A-Z]{12,}|xox[abprs]-[A-Za-z0-9-]{6,}"
    r"|eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{2,}\.|AIza[A-Za-z0-9_-]{16,}|glpat-[A-Za-z0-9_-]{10,}"
    r"|npm_[A-Za-z0-9]{10,}|hf_[A-Za-z0-9]{10,}"
    r"|(?:bearer|passw(?:or)?d|pwd|api[-_ ]?key)\s+(?=\S*\d)\S{8,})",
    re.I,
)
_PATH_SHAPE = re.compile(
    r"(^|[\s(\"'=:])(/[A-Za-z0-9._-]+/|~[A-Za-z0-9_-]*/|[A-Za-z]:\\|\\\\"
    r"|(?:Users|home|var|private|tmp|etc|opt|usr|mnt|Volumes|root)/[A-Za-z0-9._-]+)"
    r"|\.\./|[\u2215\u2044\uff0f\u29f8]"
)
_FILE_EXT = re.compile(r"\.[A-Za-z0-9]{1,6}$")


def _has_relative_path(text: str) -> bool:
    for tok in text.split():
        inner = tok.removeprefix("./").strip("/")
        if "/" not in inner:
            continue
        if _FILE_EXT.search(tok.rstrip("/,;:)")) or any(
            _SENSITIVE_SEGMENT.match(seg) for seg in inner.split("/")
        ):
            return True
    return False


def _scrub(value: Any, limit: int = 80) -> str | None:
    """Short label that is safe to commit.

    Anything that looks like a path, a credential, or a key/password assignment replaces the whole
    label with a marker; a plain label is only length-bounded.
    """
    if not isinstance(value, str) or not value.strip():
        return None
    clean = "".join(ch for ch in value[: limit * 8] if unicodedata.category(ch) != "Cf")
    text = " ".join(clean.split(maxsplit=limit))[: limit * 4]
    window = text[: limit * 2]
    if _PATH_SHAPE.search(window) or _has_relative_path(window):
        return "[redacted: contains a path]"
    if (
        _CREDENTIAL_SHAPES.search(window)
        or _TOKEN_ASSIGNMENT.search(window)
        or (_SECRET_WORDS.search(window) and re.search(r"[=:]\s*\S{3,}", window))
    ):
        return "[redacted]"
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _opaque_id(value: Any, prefix: str) -> str:
    """Return the id when it is a plain token, else a short hash; ids come from file names."""
    s = value if isinstance(value, str) else ""
    if _OPAQUE_ID_RE.match(s) and not _CREDENTIAL_SHAPES.search(s):
        return s
    return f"{prefix}-{hashlib.sha256(s.encode()).hexdigest()[:10]}"


_MESSAGE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


def _message_id(value: Any) -> str:
    if (
        isinstance(value, str)
        and _MESSAGE_ID_RE.match(value)
        and not _CREDENTIAL_SHAPES.search(value)
    ):
        return value
    return _opaque_id(value, "msg")


def _tool_use_id(value: Any) -> str:
    if isinstance(value, str) and _TOOL_USE_RE.match(value):
        return value
    return _opaque_id(value, "spawn")


def _safe_description(value: Any) -> str | None:
    """Short label for a subagent; text that looks like a path is redacted before it is committed."""
    return _scrub(value)


def _is_count(v: Any) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


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
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    r = json.loads(line)
                except (ValueError, RecursionError):
                    bad += 1
                    continue
                if isinstance(r, dict):
                    rows.append(r)
                else:
                    bad += 1
    except OSError:
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
    return (start is None or t >= start) and (end is None or t < end)


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


def _group_by_message_id(
    rows: list[dict[str, Any]],
) -> tuple[dict[str, list[dict[str, Any]]], list[str], list[dict[str, Any]]]:
    by_id: dict[str, list[dict[str, Any]]] = {}
    order: list[str] = []
    no_id: list[dict[str, Any]] = []
    for r in rows:
        mid = r["message"].get("id")
        if not isinstance(mid, str) or not mid:
            no_id.append(r)
            continue
        if mid not in by_id:
            by_id[mid] = []
            order.append(mid)
        by_id[mid].append(r)
    return by_id, order, no_id


def _output_rank(row: dict[str, Any]) -> int:
    out = row["message"]["usage"].get("output_tokens")
    return out if _is_count(out) else -1


def _dedupe(
    by_id: dict[str, list[dict[str, Any]]], order: list[str]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    chosen: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []
    for mid in order:
        group = by_id[mid]
        nums = [_row_numbers(g["message"]["usage"]) for g in group]
        if all(n == nums[0] for n in nums):
            chosen.append(group[0])
            continue
        chosen.append(max(group, key=_output_rank))
        conflicts.append(
            {
                "message_id": _message_id(mid),
                "conflict": True,
                "raw_rows": [{k: v if _is_count(v) else None for k, v in n.items()} for n in nums],
            }
        )
    return chosen, conflicts


def _partial_ids(
    order: list[str], urows: list[dict[str, Any]], all_urows: list[dict[str, Any]] | None
) -> list[str]:
    if all_urows is None:
        return []

    def counts(rows: list[dict[str, Any]]) -> Counter[str]:
        return Counter(r["message"]["id"] for r in rows if isinstance(r["message"].get("id"), str))

    full, seen = counts(all_urows), counts(urows)
    return [_message_id(m) for m in order if full[m] > seen[m]]


def _sum_tokens(chosen: list[dict[str, Any]], source: str) -> dict[str, Any]:
    tokens: dict[str, Any] = {}
    for name, field in TOKEN_FIELDS.items():
        present = [v for v in (c["message"]["usage"].get(field) for c in chosen) if _is_count(v)]
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
    return tokens


def _context_tokens(chosen: list[dict[str, Any]], source: str) -> dict[str, Any]:
    ins = [c["message"]["usage"].get("input_tokens") for c in chosen]
    outs = [c["message"]["usage"].get("output_tokens") for c in chosen]
    last_in = next((v for v in reversed(ins) if _is_count(v)), None)
    known_outs = [v for v in outs if _is_count(v)]
    known_ins = [v for v in ins if _is_count(v)]
    if last_in is None:
        return {
            "last_context_tokens": missing(source),
            "max_context_tokens": missing(source),
            "reported_context_total": missing(source),
        }
    total = (
        metric(
            last_in + sum(known_outs),
            source,
            note="final-turn input + summed output; the figure the harness reports for subagents, not billed usage",
        )
        if known_outs
        else missing(source, "no row carried output_tokens")
    )
    return {
        "last_context_tokens": metric(
            last_in, source, note="input tokens of the final turn: context size, not usage"
        ),
        "max_context_tokens": metric(
            max(known_ins), source, note="largest per-turn input: context size, not usage"
        ),
        "reported_context_total": total,
    }


def _model_labels(chosen: list[dict[str, Any]]) -> list[str]:
    models: list[str] = []
    for c in chosen:
        label = _scrub(c["message"].get("model"), 60)
        if label is not None and label not in models:
            models.append(label)
    return models


def _scope_usage(
    rows: list[dict[str, Any]], source: str, all_rows: list[dict[str, Any]] | None = None
) -> dict[str, Any]:
    """Deduplicate usage rows by message id within one scope and sum tokens."""
    all_urows = _usage_rows(all_rows) if all_rows is not None else None
    usage_rows = _usage_rows(rows)
    urows = [r for r in usage_rows if r["message"].get("model") != "<synthetic>"]
    by_id, order, no_id = _group_by_message_id(urows)
    chosen, conflicts = _dedupe(by_id, order)
    chosen.extend(no_id)
    return {
        "tokens": {**_sum_tokens(chosen, source), **_context_tokens(chosen, source)},
        "usage_rows": len(urows),
        "distinct_message_ids": len(order),
        "rows_without_message_id": len(no_id),
        "synthetic_rows_ignored": len(usage_rows) - len(urows),
        "partial_message_ids": _partial_ids(order, urows, all_urows),
        "conflicts": conflicts,
        "models": _model_labels(chosen),
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


def _finite_number(v: Any) -> bool:
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return False
    try:
        return math.isfinite(v)
    except OverflowError:
        return False


def _turn_time(rows: list[dict[str, Any]]) -> dict[str, Any]:
    vals = [
        r["durationMs"]
        for r in rows
        if r.get("type") == "system"
        and r.get("subtype") == "turn_duration"
        and _finite_number(r.get("durationMs"))
    ]
    if not vals:
        return missing("no turn_duration records")
    try:
        total = sum(vals)
        unusable = not math.isfinite(total) or total > 1e13
    except OverflowError:
        unusable = True
    if unusable:
        return missing("turn_duration records sum to an unusable value")
    return metric(
        int(total),
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
    seen_ids: set[str] = set()
    for path in sorted(sub_dir.rglob("agent-*.jsonl")):
        raw_id = path.stem[len("agent-") :]
        rel = str(path.relative_to(sub_dir))
        agent_id = _opaque_id(raw_id, "agent")
        if agent_id in seen_ids:
            agent_id = f"{agent_id}-{hashlib.sha256(rel.encode()).hexdigest()[:6]}"
        seen_ids.add(agent_id)
        all_sub_rows, bad = _read_rows(path)
        rows = [r for r in all_sub_rows if _in_window(r, start, end)]
        if not rows:
            continue
        meta: dict[str, Any] = {}
        meta_path = path.with_suffix(".meta.json")
        if meta_path.is_file():
            try:
                loaded = json.loads(meta_path.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    meta = loaded
            except (ValueError, RecursionError, OSError):
                pass
        scope = _scope_usage(rows, "subagent usage rows", all_sub_rows)
        dur = _span_ms(rows)
        out.append(
            {
                "agent_id": agent_id,
                "parent_session_id": session_id[:8] if _UUID_RE.match(session_id) else "session",
                "tool_use_id": meta["toolUseId"]
                if isinstance(meta.get("toolUseId"), str) and _TOOL_USE_RE.match(meta["toolUseId"])
                else None,
                "agent_type": _scrub(meta.get("agentType"), 40),
                "description": _safe_description(meta.get("description")),
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
                "partial_message_ids": scope["partial_message_ids"],
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
            results[_scrub(r.get("result"), 30) or "unknown"] += 1
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
    except (ValueError, RecursionError, OSError):
        return missing("harness-verify report is not valid JSON")
    if not isinstance(data, dict):
        return missing("harness-verify report is not a JSON object")
    dur = data.get("total_duration_ms")
    gates: list[dict[str, Any]] = []
    raw_gates = data.get("gates")
    for g in raw_gates if isinstance(raw_gates, list) else []:
        if isinstance(g, dict):
            gates.append(
                {
                    "name": _scrub(g.get("name"), 40),
                    "status": _scrub(g.get("status"), 20),
                    "duration_ms": g["duration_ms"] if _is_count(g.get("duration_ms")) else None,
                }
            )
    failed = data.get("failed")
    return metric(
        {
            "status": _scrub(data.get("status"), 20),
            "total_duration_ms": dur if _is_count(dur) else None,
            "gates": gates,
            "failed": [x for x in (_scrub(f, 40) for f in failed) if x]
            if isinstance(failed, list)
            else [],
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
    no_ts = (
        sum(1 for r in all_rows if _usage_rows([r]) and not isinstance(r.get("timestamp"), str))
        if (t_start or t_end)
        else 0
    )

    parent = _scope_usage(rows, "session usage rows", all_rows)
    parent["malformed_lines"] = bad
    parent["rows_without_timestamp_excluded"] = no_ts
    subs = _subagents(session_file.parent, session_id, t_start, t_end)

    spawns = _spawn_ids(rows)
    matched = {s["tool_use_id"] for s in subs}
    for s in subs:
        s["spawned_by_parent_call"] = s["tool_use_id"] in spawns
    wall = _span_ms(rows)
    agent_ms = [s["duration_ms"]["value"] for s in subs if s["duration_ms"]["value"] is not None]

    key = f"{session_id}|{start or ''}|{end or ''}"
    short_id = session_id[:8] if _UUID_RE.match(session_id) else "session"
    run_id = f"{short_id}-{hashlib.sha256(key.encode()).hexdigest()[:10]}"
    return {
        "run_id": run_id,
        "schema_version": 1,
        "session_id": short_id,
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
        "unmatched_spawns": [_tool_use_id(s) for s in spawns if s not in matched],
        "subagents_without_spawn": [s["agent_id"] for s in subs if not s["spawned_by_parent_call"]],
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


def find_session_file(projects_dir: Path, session_id: str) -> Path | None:
    if not _UUID_RE.match(session_id):
        return None
    matches = [p for p in projects_dir.glob(f"*/{session_id}.jsonl") if p.is_file()]
    return max(matches, key=lambda p: (p.stat().st_mtime, str(p)), default=None)


def last_recorded_end(runs_dir: Path, short_id: str, now: datetime | None = None) -> str | None:
    """Latest window end among records of this session; open-ended, unreadable and future-dated records are skipped."""
    limit = now or datetime.now(timezone.utc)
    best: tuple[datetime, str] | None = None
    for p in sorted(runs_dir.glob("*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            if not isinstance(data, dict) or data.get("session_id") != short_id:
                continue
            end = data["window"]["end"]
            t = parse_ts(end)
        except (OSError, ValueError, RecursionError, KeyError, TypeError, AttributeError):
            continue
        if t > limit:
            continue
        if best is None or t > best[0]:
            best = (t, end)
    return best[1] if best else None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Collect run telemetry from a Claude Code session file."
    )
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--session", type=Path, help="session transcript .jsonl")
    src.add_argument(
        "--current-session",
        action="store_true",
        help="use $CLAUDE_CODE_SESSION_ID, from the end of its last record until now",
    )
    ap.add_argument("--projects-dir", type=Path, default=Path.home() / ".claude" / "projects")
    ap.add_argument("--start", help="window start (ISO timestamp)")
    ap.add_argument("--end", help="window end (ISO timestamp)")
    ap.add_argument("--verify-report", type=Path, help="harness-verify.sh --report JSON")
    ap.add_argument("--outside-log", type=Path, help="outside-agent-runs.jsonl")
    ap.add_argument("--out-dir", type=Path, default=Path("docs/telemetry/runs"))
    args = ap.parse_args(argv)
    start, end = args.start, args.end
    if args.current_session:
        session_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
        found = find_session_file(args.projects_dir, session_id)
        if found is None:
            print("run_telemetry: no transcript for the current session id", file=sys.stderr)
            return 2
        args.session = found
        short_id = session_id[:8]
        start = start or last_recorded_end(args.out_dir, short_id)
        end = end or datetime.now(timezone.utc).isoformat()
    if not args.session.is_file():
        print(f"run_telemetry: session file not found: {args.session}", file=sys.stderr)
        return 2
    try:
        run = collect_run(
            args.session,
            start=start,
            end=end,
            verify_report=args.verify_report,
            outside_log=args.outside_log,
        )
    except ValueError as e:
        print(f"run_telemetry: bad timestamp: {e}", file=sys.stderr)
        return 2
    if args.current_session and run["parent"]["usage_rows"] == 0:
        print(
            f"run_telemetry: no activity since {start or 'the start of the session'}; nothing written"
        )
        return 0
    args.out_dir.mkdir(parents=True, exist_ok=True)
    out = args.out_dir / f"{run['run_id']}.json"
    out.write_text(json.dumps(run, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
