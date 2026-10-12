#!/usr/bin/env python3
"""trace_evaluation.py — Trace and evaluate repository metrics over time.

Collects snapshot metrics of multi-agent identity, total task spent time,
state layer token overhead, feature velocity, test counts, and threshold alerts,
storing them in docs/telemetry/evaluation-trace.jsonl.
Provides historical trend reporting and regression alerting across agents.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

# macOS system Python 3.9 compatibility (datetime.UTC was added in 3.11)
UTC = getattr(_dt, "UTC", _dt.timezone.utc)  # noqa: UP017

# Default warning thresholds to prevent context bloat
THRESHOLD_FEATURE_LIST_LINES = 250
THRESHOLD_PROGRESS_LINES = 150
THRESHOLD_STATE_TOKENS = 6000


def get_git_commit(repo_dir: Path) -> str:
    """Return short commit SHA, or 'unknown' if not inside git repo."""
    try:
        res = subprocess.run(
            ["git", "-C", str(repo_dir), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
        return res.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return "unknown"


def get_process_ancestors(max_depth: int = 6) -> list[str]:
    """Return command/process names of ancestors up to max_depth."""
    ancestors: list[str] = []
    pid = os.getpid()
    try:
        for _ in range(max_depth):
            res = subprocess.run(
                ["ps", "-o", "ppid=,comm=", "-p", str(pid)],
                capture_output=True,
                text=True,
                check=True,
            )
            line = res.stdout.strip()
            if not line:
                break
            parts = line.split(None, 1)
            if not parts:
                break
            ppid_str = parts[0]
            comm = parts[1] if len(parts) > 1 else ""
            if comm:
                ancestors.append(comm.lower())
            ppid = int(ppid_str)
            if ppid <= 1:
                break
            pid = ppid
    except (subprocess.SubprocessError, OSError, ValueError):
        pass
    return ancestors


def detect_agent(explicit_agent: str | None = None) -> str:
    """Detect current AI agent runtime environment or use explicit parameter."""
    if explicit_agent and explicit_agent not in ("auto", "none", ""):
        return explicit_agent.lower()

    # 1. Inspect parent process ancestry
    for comm in get_process_ancestors():
        base = Path(comm).name.lower()
        if "agy" in base or "antigravity" in base:
            return "agy"
        if "claude" in base:
            return "claude"
        if "codex" in base:
            return "codex"
        if "kiro" in base:
            return "kiro"

    # 2. Inspect active environment variables
    env = os.environ
    if (
        "GEMINI_CONFIG_DIR" in env
        or "AGY_VERSION" in env
        or "ANTIGRAVITY_AGENT" in env
        or "ANTIGRAVITY_CLI" in env
    ):
        return "agy"
    if "CLAUDE_PROJECT_DIR" in env or "CLAUDE_CODE" in env or "ANTHROPIC_API_KEY" in env:
        return "claude"
    if "CODEX_HOME" in env or "CODEX_CLI" in env:
        return "codex"
    if "KIRO_HOME" in env or "KIRO_IDE" in env:
        return "kiro"

    return "unknown"


def auto_detect_duration_ms(trace_path: Path, repo_dir: Path) -> float | None:
    """Auto-detect elapsed active time since previous trace entry or commit.

    Ignores inter-session idle pauses (>30 minutes) to prevent human waiting
    time from inflating agent active milestone durations.
    """
    IDLE_BREAK_THRESHOLD_SEC = 1800.0  # 30 minutes

    # 1. Check previous trace entry timestamp
    if trace_path.is_file():
        try:
            last_line = ""
            with open(trace_path, "r", encoding="utf-8") as f:
                for line in f:
                    if line.strip():
                        last_line = line.strip()
            if last_line:
                data = json.loads(last_line)
                prev_ts_str = data.get("timestamp")
                if prev_ts_str:
                    prev_dt = datetime.fromisoformat(prev_ts_str)
                    now_dt = datetime.now(UTC)
                    delta_sec = (now_dt - prev_dt).total_seconds()
                    # Return active duration if within session boundary
                    if 0 < delta_sec <= IDLE_BREAK_THRESHOLD_SEC:
                        return delta_sec * 1000
        except (json.JSONDecodeError, ValueError, OSError):
            pass

    # 2. Try git commit timestamp delta if trace delta spanned an idle break
    try:
        res = subprocess.run(
            ["git", "-C", str(repo_dir), "log", "-2", "--format=%ct"],
            capture_output=True,
            text=True,
            check=True,
        )
        lines = [
            int(x.strip())
            for x in res.stdout.strip().split()
            if x.strip().isdigit()
        ]
        if len(lines) >= 2:
            delta_sec = lines[0] - lines[1]
            if 0 < delta_sec <= IDLE_BREAK_THRESHOLD_SEC:
                return float(delta_sec * 1000)
    except (subprocess.SubprocessError, OSError, ValueError):
        pass

    return None


def format_duration(ms: float | None) -> str:
    """Format millisecond duration into human-readable string."""
    if ms is None or ms <= 0:
        return "-"
    if ms < 1000:
        return f"{int(ms)}ms"
    sec = ms / 1000
    if sec < 60:
        return f"{sec:.1f}s"
    minutes = int(sec // 60)
    remaining_sec = int(sec % 60)
    if minutes < 60:
        return f"{minutes}m {remaining_sec}s"
    hours = int(minutes // 60)
    rem_min = int(minutes % 60)
    return f"{hours}h {rem_min}m"


def count_lines(file_path: Path) -> int:
    """Return line count of a file, or 0 if missing."""
    if not file_path.is_file():
        return 0
    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            return sum(1 for _ in f)
    except OSError:
        return 0


def estimate_tokens(file_path: Path) -> int:
    """Estimate token count based on character length (~4 characters per token)."""
    if not file_path.is_file():
        return 0
    try:
        size_chars = file_path.stat().st_size
        return max(1, size_chars // 4)
    except OSError:
        return 0


def format_subagents(sub: dict[str, Any] | None) -> str:
    """Format subagents telemetry into human-readable string."""
    if not sub or not isinstance(sub, dict):
        return "-"
    try:
        self_c = int(sub.get("self_count") or 0)
    except (TypeError, ValueError):
        self_c = 0
    try:
        out_c = int(sub.get("outside_count") or 0)
    except (TypeError, ValueError):
        out_c = 0

    raw_used = sub.get("outside_used") or []
    used: list[str] = []
    if isinstance(raw_used, list):
        for item in raw_used:
            if item is not None:
                used.append(str(item))

    if self_c == 0 and out_c == 0:
        return "-"
    parts: list[str] = []
    if self_c > 0:
        parts.append(f"{self_c} self")
    if out_c > 0:
        names = f" ({','.join(used)})" if used else ""
        parts.append(f"{out_c} out{names}")
    return ", ".join(parts)


def auto_detect_outside_runs(
    repo_dir: Path, since_ts_iso: str | None = None
) -> list[dict[str, Any]]:
    """Detect outside agent runs since the specified timestamp (or last 30 minutes)."""
    custom_dir = os.environ.get("OUTSIDE_AGENT_DIR")
    runtime_base = Path(custom_dir) if custom_dir else Path.home() / ".agent-skills-setup"
    candidates: list[tuple[Path, bool]] = [
        (repo_dir / "docs" / "telemetry" / "outside-agent-runs.jsonl", True),
        (runtime_base / "state" / "outside-agent-runs.jsonl", False),
    ]
    runs: list[dict[str, Any]] = []
    cutoff_dt: datetime | None = None
    if since_ts_iso:
        try:
            cutoff_dt = datetime.fromisoformat(since_ts_iso)
        except (ValueError, TypeError):
            pass
    if cutoff_dt is None:
        cutoff_dt = datetime.now(UTC) - timedelta(minutes=30)

    # Normalize cutoff_dt to timezone-aware UTC
    if cutoff_dt.tzinfo is None:
        cutoff_dt = cutoff_dt.replace(tzinfo=UTC)

    resolved_repo_str = str(repo_dir.resolve())

    for p, is_local_repo in candidates:
        if not p.is_file():
            continue
        try:
            with open(p, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                        if not isinstance(rec, dict):
                            continue
                        # If reading global runtime state, require matching repo
                        if not is_local_repo:
                            rec_repo = rec.get("repo")
                            if not rec_repo or rec_repo != resolved_repo_str:
                                continue
                        ts_val = rec.get("timestamp")
                        if not isinstance(ts_val, str):
                            continue
                        rec_dt = datetime.fromisoformat(ts_val)
                        if rec_dt.tzinfo is None:
                            rec_dt = rec_dt.replace(tzinfo=UTC)
                        if rec_dt >= cutoff_dt:
                            runs.append(rec)
                    except (json.JSONDecodeError, ValueError, TypeError, AttributeError):
                        continue
        except OSError:
            pass
        if runs:
            break
    return runs


def _state_metrics(repo_dir: Path) -> dict[str, int]:
    """Measure the state layer: sizes, feature counts, and test file count."""
    feature_file = repo_dir / "feature_list.json"
    progress_file = repo_dir / "PROGRESS.md"

    feat_tokens = estimate_tokens(feature_file)
    prog_tokens = estimate_tokens(progress_file)

    completed = active = total = archive_refs = 0
    if feature_file.is_file():
        try:
            with open(feature_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                archive_refs = len(data.get("archive_references", []))
                features = data.get("features", [])
                total = len(features)
                for feat in features:
                    status = feat.get("status", "")
                    if status in ("completed", "done"):
                        completed += 1
                    elif status in ("in_progress", "in-progress", "active"):
                        active += 1
        except (json.JSONDecodeError, OSError):
            pass

    test_files = 0
    for d in (
        repo_dir / "scripts" / "tests",
        repo_dir / "harness" / "guards" / "tests",
        repo_dir / "tests",
    ):
        if d.is_dir():
            test_files += sum(1 for p in d.glob("test_*.*") if p.suffix in (".sh", ".py"))

    return {
        "feat_lines": count_lines(feature_file),
        "prog_lines": count_lines(progress_file),
        "feat_tokens": feat_tokens,
        "prog_tokens": prog_tokens,
        "total_tokens": feat_tokens + prog_tokens,
        "completed": completed,
        "active": active,
        "total": total,
        "archive_refs": archive_refs,
        "test_files": test_files,
    }


def _threshold_warnings(metrics: dict[str, int]) -> list[str]:
    warnings: list[str] = []
    if metrics["feat_lines"] > THRESHOLD_FEATURE_LIST_LINES:
        warnings.append(
            f"feature_list.json exceeds {THRESHOLD_FEATURE_LIST_LINES} lines "
            f"({metrics['feat_lines']} lines) — archival to docs/archive/features/ recommended."
        )
    if metrics["prog_lines"] > THRESHOLD_PROGRESS_LINES:
        warnings.append(
            f"PROGRESS.md exceeds {THRESHOLD_PROGRESS_LINES} lines "
            f"({metrics['prog_lines']} lines) — session log pruning recommended."
        )
    if metrics["total_tokens"] > THRESHOLD_STATE_TOKENS:
        warnings.append(
            f"State layer tokens exceed {THRESHOLD_STATE_TOKENS} tokens "
            f"(~{metrics['total_tokens']:,} tokens) — context bloat detected."
        )
    return warnings


def check_thresholds(repo_dir: Path) -> list[str]:
    """Return threshold warnings for the state layer without gathering agent telemetry."""
    return _threshold_warnings(_state_metrics(repo_dir))


def load_records(trace_path: Path) -> list[dict[str, Any]]:
    """Read the JSONL trace, skipping blank and malformed lines."""
    if not trace_path.is_file():
        return []
    records: list[dict[str, Any]] = []
    with open(trace_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def trace_row(rec: dict[str, Any]) -> dict[str, str]:
    """Format one trace record into the display fields shared by the trend and dashboard."""
    sl = rec.get("state_layer", {})
    return {
        "commit": rec.get("commit", "unknown"),
        "ts": rec.get("timestamp", "")[:19].replace("T", " "),
        "agent": rec.get("agent", "unknown"),
        "subagents": format_subagents(rec.get("subagents")),
        "duration": rec.get("duration_str") or format_duration(rec.get("duration_ms", 0)),
        "tokens": f"~{sl.get('total_state_tokens_est', 0):,} tok",
        "feat_lines": f"{sl.get('feature_list_lines', 0)} lines",
        "prog_lines": f"{sl.get('progress_lines', 0)} lines",
        "done_active": f"{sl.get('completed_features', 0)} ({sl.get('active_features', 0)} act)",
        "status": rec.get("thresholds", {}).get("status", "OK"),
    }


def collect_snapshot(
    repo_dir: Path,
    trace_path: Path | None = None,
    explicit_agent: str | None = None,
    duration_ms: float | None = None,
    self_subagents: int | None = None,
    outside_subagents: str | None = None,
) -> dict[str, Any]:
    """Gather all evaluation metrics for the current repository state."""
    commit = get_git_commit(repo_dir)
    now_iso = datetime.now(UTC).isoformat()
    agent_name = detect_agent(explicit_agent)

    if (duration_ms is None or duration_ms <= 0) and trace_path is not None:
        duration_ms = auto_detect_duration_ms(trace_path, repo_dir)

    dur_str = format_duration(duration_ms)

    # Subagents detection & parsing
    self_c = self_subagents if self_subagents is not None else 0
    outside_used: list[str] = []
    outside_c = 0
    indep_verified = False

    if outside_subagents:
        for part in outside_subagents.split(","):
            part = part.strip()
            if part.isdigit():
                outside_c += int(part)
            elif part:
                outside_used.append(part)
                outside_c += 1
                indep_verified = True
    else:
        since_ts = None
        if trace_path and trace_path.is_file():
            try:
                with open(trace_path, "r", encoding="utf-8") as f:
                    lines = [ln.strip() for ln in f if ln.strip()]
                    if lines:
                        last_rec = json.loads(lines[-1])
                        if isinstance(last_rec, dict):
                            since_ts = last_rec.get("timestamp")
            except (json.JSONDecodeError, OSError, TypeError, AttributeError):
                pass
        runs = auto_detect_outside_runs(repo_dir, since_ts_iso=since_ts)
        for r in runs:
            ag = r.get("agent")
            if ag and ag not in outside_used:
                outside_used.append(ag)
            outside_c += 1
            if r.get("independent", False):
                indep_verified = True

    subagents_data = {
        "self_count": self_c,
        "outside_count": outside_c,
        "outside_used": outside_used,
        "independent_verified": indep_verified,
    }

    metrics = _state_metrics(repo_dir)
    warnings = _threshold_warnings(metrics)
    status_str = "WARN" if warnings else "OK"

    return {
        "commit": commit,
        "timestamp": now_iso,
        "agent": agent_name,
        "subagents": subagents_data,
        "duration_ms": duration_ms or 0,
        "duration_str": dur_str,
        "state_layer": {
            "feature_list_lines": metrics["feat_lines"],
            "feature_list_tokens_est": metrics["feat_tokens"],
            "progress_lines": metrics["prog_lines"],
            "progress_tokens_est": metrics["prog_tokens"],
            "total_state_tokens_est": metrics["total_tokens"],
            "completed_features": metrics["completed"],
            "active_features": metrics["active"],
            "total_features": metrics["total"],
            "archive_references": metrics["archive_refs"],
        },
        "test_metrics": {
            "test_suites_count": metrics["test_files"],
        },
        "thresholds": {
            "status": status_str,
            "warnings": warnings,
        },
    }


def render_markdown_dashboard(trace_path: Path, output_md: Path | None = None) -> str:
    """Render a GitHub-flavored Markdown dashboard table from trace history."""
    records = load_records(trace_path)
    if not records:
        return ""

    md_lines = [
        "# Repository Evaluation & Telemetry Dashboard",
        "",
        "*Automated execution telemetry, multi-agent state evolution, and state layer tracking.*",
        "",
        "| Commit | Timestamp (UTC) | Agent | Subagents | Spent Time | Est. Tokens | `feature_list.json` | `PROGRESS.md` | Done (Active) | Status |",
        "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
    ]

    latest_warnings: list[str] = []
    for rec in records[-20:]:
        r = trace_row(rec)
        latest_warnings = rec.get("thresholds", {}).get("warnings", [])
        md_lines.append(
            f"| `{r['commit']}` | {r['ts']} | `{r['agent']}` | {r['subagents']} | {r['duration']} | "
            f"{r['tokens']} | {r['feat_lines']} | {r['prog_lines']} | {r['done_active']} | **{r['status']}** |"
        )

    md_lines.append("")
    if latest_warnings:
        md_lines.append("### Actionable Remediation & Suggestions")
        for w in latest_warnings:
            md_lines.append(f"- ⚠️ **[ACTION]** {w}")
    else:
        md_lines.append("✅ **Status:** All state layer metrics are within clean-state limits.")
    md_lines.append("")

    content = "\n".join(md_lines)
    if output_md:
        output_md.parent.mkdir(parents=True, exist_ok=True)
        with open(output_md, "w", encoding="utf-8") as f:
            f.write(content)

    return content


def record_snapshot(
    repo_dir: Path,
    trace_path: Path,
    explicit_agent: str | None = None,
    duration_ms: float | None = None,
    self_subagents: int | None = None,
    outside_subagents: str | None = None,
) -> dict[str, Any]:
    """Record current snapshot to JSONL file and update Markdown dashboard."""
    snapshot = collect_snapshot(
        repo_dir,
        trace_path=trace_path,
        explicit_agent=explicit_agent,
        duration_ms=duration_ms,
        self_subagents=self_subagents,
        outside_subagents=outside_subagents,
    )
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    with open(trace_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(snapshot) + "\n")

    summary_path = trace_path.parent / "SUMMARY.md"
    render_markdown_dashboard(trace_path, output_md=summary_path)

    return snapshot


def render_trend_table(trace_path: Path) -> None:
    """Read trace file and display formatted history table."""
    if not trace_path.is_file():
        print(f"No evaluation trace history found at: {trace_path}")
        return

    records = load_records(trace_path)
    if not records:
        print(f"No records found in {trace_path}")
        return

    print("=" * 136)
    print(" EVALUATION TRACE HISTORY & MULTI-AGENT STATE EVOLUTION")
    print("=" * 136)
    print(
        f"{'Commit':<10} {'Timestamp':<20} {'Agent':<8} {'Subagents':<22} {'Spent Time':<12} "
        f"{'Est. Tokens':<14} {'feat.json':<12} {'prog.md':<10} {'Done (Active)':<14} {'Status':<6}"
    )
    print("-" * 136)

    latest_warnings: list[str] = []
    for rec in records[-15:]:  # Show last 15 entries
        r = trace_row(rec)
        latest_warnings = rec.get("thresholds", {}).get("warnings", [])
        print(
            f"{r['commit']:<10} {r['ts']:<20} {r['agent']:<8} {r['subagents']:<22} {r['duration']:<12} "
            f"{r['tokens']:<14} {r['feat_lines']:<12} {r['prog_lines']:<10} {r['done_active']:<14} "
            f"{r['status']:<6}"
        )

    print("=" * 136)
    if latest_warnings:
        print("\nActionable Remediation & Suggestions:")
        for w in latest_warnings:
            print(f"  [ACTION] {w}")
    else:
        print("\nStatus: All state layer metrics are within clean-state limits.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Repository evaluation trace loop and trend reporter."
    )
    parser.add_argument(
        "--repo-dir",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Path to repository root",
    )
    parser.add_argument(
        "--agent",
        type=str,
        default=None,
        help="Agent identifier (default: auto-detected agy, claude, codex, kiro)",
    )
    parser.add_argument(
        "--duration-ms",
        type=int,
        default=None,
        help="Total task / session duration in milliseconds",
    )
    parser.add_argument(
        "--self-subagents",
        type=int,
        default=None,
        help="Count of self/internal subagents dispatched in this milestone",
    )
    parser.add_argument(
        "--outside-subagents",
        type=str,
        default=None,
        help="Outside agents used (e.g. 'claude' or count '1')",
    )
    parser.add_argument(
        "--record",
        nargs="?",
        const="DEFAULT",
        default=None,
        help="Append snapshot to target trace file (default: docs/telemetry/evaluation-trace.jsonl)",
    )
    parser.add_argument(
        "--trend",
        nargs="?",
        const="DEFAULT",
        default=None,
        help="Render history table from target trace file",
    )
    parser.add_argument(
        "--markdown",
        nargs="?",
        const="DEFAULT",
        default=None,
        help="Render Markdown dashboard from target trace file",
    )
    parser.add_argument(
        "--check-thresholds",
        action="store_true",
        help="Evaluate warning thresholds and exit non-zero if bloat detected",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit current snapshot payload as JSON to stdout",
    )

    args = parser.parse_args()
    repo_dir = args.repo_dir.resolve()
    default_trace_file = repo_dir / "docs" / "telemetry" / "evaluation-trace.jsonl"

    if args.json:
        snapshot = collect_snapshot(
            repo_dir,
            trace_path=default_trace_file,
            explicit_agent=args.agent,
            duration_ms=args.duration_ms,
            self_subagents=args.self_subagents,
            outside_subagents=args.outside_subagents,
        )
        print(json.dumps(snapshot, indent=2))
        return 0

    if args.check_thresholds:
        warnings = check_thresholds(repo_dir)
        if warnings:
            print("WARNING: Repository state thresholds breached:")
            for w in warnings:
                print(f"  - {w}")
            return 1
        print("OK: All state layer thresholds within limits.")
        return 0

    if args.trend is not None:
        target = default_trace_file if args.trend == "DEFAULT" else Path(args.trend)
        render_trend_table(target)
        return 0

    if args.markdown is not None:
        target = default_trace_file if args.markdown == "DEFAULT" else Path(args.markdown)
        md = render_markdown_dashboard(target)
        if md:
            print(md)
        else:
            print(f"No records found in {target}")
        return 0

    # Default action or --record
    target_trace = (
        default_trace_file
        if (args.record is None or args.record == "DEFAULT")
        else Path(args.record)
    )
    snapshot = record_snapshot(
        repo_dir,
        target_trace,
        explicit_agent=args.agent,
        duration_ms=args.duration_ms,
        self_subagents=args.self_subagents,
        outside_subagents=args.outside_subagents,
    )
    sub_disp = format_subagents(snapshot.get("subagents"))
    print(f"Recorded evaluation trace snapshot to: {target_trace}")
    print(
        f"  Commit: {snapshot['commit']} | Agent: {snapshot['agent']} | "
        f"Subagents: {sub_disp} | "
        f"Spent Time: {snapshot['duration_str']} | "
        f"Tokens: ~{snapshot['state_layer']['total_state_tokens_est']:,} est "
        f"(feat={snapshot['state_layer']['feature_list_tokens_est']:,}, prog={snapshot['state_layer']['progress_tokens_est']:,}) | "
        f"State Lines: feature_list={snapshot['state_layer']['feature_list_lines']}, "
        f"PROGRESS={snapshot['state_layer']['progress_lines']} | "
        f"Status: {snapshot['thresholds']['status']}"
    )

    if snapshot["thresholds"]["warnings"]:
        for w in snapshot["thresholds"]["warnings"]:
            print(f"  [WARN] {w}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
