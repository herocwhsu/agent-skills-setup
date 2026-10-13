#!/usr/bin/env python3
"""Attach a run record to each completed feature and keep the state layer within budget.

A feature's window ends at the first commit where feature_list.json shows it completed and starts
where the last record of the same session ended. The summary written into the feature repeats the
fields of the run record that matter; the full record stays in docs/telemetry/runs/.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import run_telemetry
import trace_evaluation

DONE = ("completed", "done")
_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)


def _git(repo: Path, *args: str) -> str:
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=False)
    return r.stdout if r.returncode == 0 else ""


def _features(data: Any) -> list[dict[str, Any]]:
    feats = data.get("features") if isinstance(data, dict) else data
    return [f for f in feats if isinstance(f, dict)] if isinstance(feats, list) else []


def _load(repo: Path) -> Any:
    try:
        return json.loads((repo / "feature_list.json").read_text(encoding="utf-8"))
    except (OSError, ValueError, RecursionError):
        return None


def completion_time(repo: Path, feature_id: str) -> str | None:
    """Commit time (ISO) of the first commit whose feature_list.json shows the feature completed."""
    log = _git(repo, "log", "--reverse", "--format=%H %cI", "--", "feature_list.json")
    for line in log.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        sha, when = parts
        try:
            data = json.loads(_git(repo, "show", f"{sha}:feature_list.json"))
        except (ValueError, RecursionError):
            continue
        for f in _features(data):
            if f.get("id") == feature_id and f.get("status") in DONE:
                return when
    return None


def windows_by_commit(repo: Path, feature_ids: list[str]) -> dict[str, list[str]]:
    groups: dict[str, list[str]] = {}
    for fid in feature_ids:
        when = completion_time(repo, fid)
        if when is not None:
            groups.setdefault(when, []).append(fid)
    return groups


def _val(m: Any) -> Any:
    return m.get("value") if isinstance(m, dict) and m.get("status") != "missing" else None


def summary_from_record(rec: dict[str, Any]) -> dict[str, Any]:
    parent_tokens = (
        rec.get("parent", {}).get("tokens", {}) if isinstance(rec.get("parent"), dict) else {}
    )
    subs = [s for s in rec.get("subagents") or [] if isinstance(s, dict)]
    sub_vals = [_val(s.get("tokens", {}).get("output_tokens_sum")) for s in subs]
    sub_out = (
        None if any(v is None for v in sub_vals) else sum(v for v in sub_vals if v is not None)
    )
    return {
        "run_id": rec.get("run_id"),
        "output_tokens": _val(parent_tokens.get("output_tokens_sum")),
        "wall_time_ms": _val(rec.get("wall_time_ms")),
        "active_turn_time_ms": _val(rec.get("active_turn_time_ms")),
        "subagents": _val(rec.get("subagent_count")),
        "subagent_output_tokens": sub_out,
    }


def apply_summary(data: Any, feature_id: str, summary: dict[str, Any]) -> bool:
    for f in _features(data):
        if f.get("id") == feature_id:
            if "execution_summary" in f:
                return False
            f["execution_summary"] = summary
            return True
    return False


def pending_features(repo: Path) -> list[str]:
    return [
        f["id"]
        for f in _features(_load(repo))
        if f.get("status") in DONE and isinstance(f.get("id"), str) and "execution_summary" not in f
    ]


def state_tokens(repo: Path) -> int:
    return trace_evaluation.estimate_tokens(
        repo / "feature_list.json"
    ) + trace_evaluation.estimate_tokens(repo / "PROGRESS.md")


def _archivable(f: dict[str, Any]) -> bool:
    return f.get("status") in DONE and bool(str(f.get("evidence") or "").strip())


def _archive_name(repo: Path, moved: list[dict[str, Any]]) -> str:
    ids = [str(f.get("id") or "x") for f in moved]
    safe = [re.sub(r"[^A-Za-z0-9_-]", "", i.removeprefix("feat-")) or "x" for i in ids]
    base = f"archive-feat-{safe[0]}-{safe[-1]}"
    name, n = f"{base}.json", 2
    while (repo / "docs" / "archive" / "features" / name).exists():
        name, n = f"{base}-{n}.json", n + 1
    return f"docs/archive/features/{name}"


def archive_to_budget(
    repo: Path, token_budget: int = trace_evaluation.THRESHOLD_STATE_TOKENS
) -> list[str]:
    """Move the oldest completed, evidenced features into a new archive file until under budget.

    The archive file is written first and the main file is replaced in one step afterwards, so a
    failure at any point leaves every feature in at least one of the two places.
    """
    data = _load(repo)
    if not isinstance(data, dict) or not isinstance(data.get("features"), list):
        return []
    if state_tokens(repo) <= token_budget:
        return []
    path = repo / "feature_list.json"
    progress = trace_evaluation.estimate_tokens(repo / "PROGRESS.md")
    feats: list[Any] = data["features"]
    kept = list(feats)
    moved: list[dict[str, Any]] = []
    for f in feats:
        if progress + (len(json.dumps(data, indent=2)) + 1) // 4 <= token_budget:
            break
        if not (isinstance(f, dict) and _archivable(f)):
            continue
        moved.append(f)
        kept = [k for k in kept if k is not f]
        data["features"] = kept
    if not moved:
        data["features"] = feats
        return []
    rel = _archive_name(repo, moved)
    out = repo / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"features": moved}, indent=2) + "\n", encoding="utf-8")
    refs = data.get("archive_references")
    refs = refs if isinstance(refs, list) else []
    data["archive_references"] = refs if rel in refs else [*refs, rel]
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)
    return [str(f.get("id")) for f in moved]


def _write_features_file(repo: Path, data: Any) -> None:
    path = repo / "feature_list.json"
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def _recorded_sibling(repo: Path, feature_id: str, end: str) -> dict[str, Any] | None:
    """A feature completed in the same commit whose summary already holds the window's numbers."""
    target = run_telemetry.parse_ts(end)
    for f in _features(_load(repo)):
        other = f.get("id")
        summary = f.get("execution_summary")
        if (
            other != feature_id
            and isinstance(other, str)
            and isinstance(summary, dict)
            and "shared_with" not in summary
            and isinstance(summary.get("run_id"), str)
            and f.get("status") in DONE
        ):
            when = completion_time(repo, other)
            if when is not None and run_telemetry.parse_ts(when) == target:
                return f
    return None


def record_feature(
    repo: Path,
    feature_id: str,
    session_id: str,
    projects_dir: Path,
    outside_log: Path | None,
    gate_report: Path | None = None,
) -> dict[str, str]:
    data = _load(repo)
    target = next((f for f in _features(data) if f.get("id") == feature_id), None)
    if target is None or target.get("status") not in DONE:
        return {"feature": feature_id, "status": "not completed"}
    if "execution_summary" in target:
        return {"feature": feature_id, "status": "already recorded"}
    end = completion_time(repo, feature_id)
    if end is None:
        return {"feature": feature_id, "status": "not completed"}
    sibling = _recorded_sibling(repo, feature_id, end)
    if sibling is not None:
        shared = {"run_id": sibling["execution_summary"]["run_id"], "shared_with": sibling["id"]}
        shared.update(
            {
                k: None
                for k in (
                    "output_tokens",
                    "wall_time_ms",
                    "active_turn_time_ms",
                    "subagents",
                    "subagent_output_tokens",
                )
            }
        )
        if apply_summary(data, feature_id, shared):
            _write_features_file(repo, data)
        return {"feature": feature_id, "status": "recorded", "run_id": str(shared["run_id"])}
    transcript = run_telemetry.find_session_file(projects_dir, session_id)
    if transcript is None:
        return {"feature": feature_id, "status": "no transcript"}
    runs_dir = repo / "docs" / "telemetry" / "runs"
    start = run_telemetry.last_recorded_end(
        runs_dir, session_id[:8], now=run_telemetry.parse_ts(end)
    )
    try:
        rec = run_telemetry.collect_run(
            transcript, start=start, end=end, outside_log=outside_log, verify_report=gate_report
        )
    except ValueError:
        return {"feature": feature_id, "status": "bad window"}
    if rec["parent"]["usage_rows"] == 0:
        return {"feature": feature_id, "status": "no activity"}
    runs_dir.mkdir(parents=True, exist_ok=True)
    (runs_dir / f"{rec['run_id']}.json").write_text(
        json.dumps(rec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    if apply_summary(data, feature_id, summary_from_record(rec)):
        _write_features_file(repo, data)
    return {"feature": feature_id, "status": "recorded", "run_id": str(rec["run_id"])}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Record run telemetry for completed features.")
    ap.add_argument("--repo", type=Path, default=Path.cwd())
    ap.add_argument("--projects-dir", type=Path, default=Path.home() / ".claude" / "projects")
    ap.add_argument("--outside-log", type=Path, default=None)
    ap.add_argument(
        "--gate-report",
        type=Path,
        default=None,
        help="harness-verify JSON; default is the last one kept",
    )
    ap.add_argument(
        "--pending", action="store_true", help="record every completed feature without a summary"
    )
    ap.add_argument("--feature", action="append", default=[], help="feature id (repeatable)")
    ap.add_argument(
        "--archive",
        action="store_true",
        help="afterwards move old completed features out of the state layer",
    )
    args = ap.parse_args(argv)
    session_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not _UUID.match(session_id):
        print(
            "feature_run_record: CLAUDE_CODE_SESSION_ID is not set to a session id", file=sys.stderr
        )
        return 2
    repo = args.repo.resolve()
    ids = list(args.feature)
    if args.pending:
        ids += [i for i in pending_features(repo) if i not in ids]
    log = args.outside_log
    if log is None:
        base = os.environ.get("OUTSIDE_AGENT_DIR")
        log = (
            (Path(base) if base else Path.home() / ".agent-skills-setup")
            / "state"
            / "outside-agent-runs.jsonl"
        )
    gate = args.gate_report
    if gate is None:
        gate = Path.home() / ".agent-skills-setup" / "state" / "harness-verify-last.json"
    order = sorted(ids, key=lambda i: completion_time(repo, i) or "")
    for fid in order:
        result = record_feature(repo, fid, session_id, args.projects_dir, log, gate)
        print(f"{result['feature']}: {result['status']}")
    if args.archive:
        moved = archive_to_budget(repo)
        if moved:
            print(f"archived {len(moved)} feature(s): {moved[0]} .. {moved[-1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
