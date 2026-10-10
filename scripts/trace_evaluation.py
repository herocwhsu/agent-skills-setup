#!/usr/bin/env python3
"""trace_evaluation.py — Trace and evaluate repository metrics over time.

Collects snapshot metrics of multi-agent identity, total task spent time,
state layer token overhead, feature velocity, test counts, and threshold alerts,
storing them in docs/telemetry/evaluation-trace.jsonl.
Provides historical trend reporting and regression alerting across agents.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

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


def detect_agent(explicit_agent: str | None = None) -> str:
    """Detect current AI agent runtime environment or use explicit parameter."""
    if explicit_agent and explicit_agent not in ("auto", "none", ""):
        return explicit_agent.lower()
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
    # Fallback checks: check presence of active antigravity or claude configs
    if Path(os.path.expanduser("~/.gemini/antigravity-cli")).is_dir():
        return "agy"
    if Path(os.path.expanduser("~/.claude")).is_dir():
        return "claude"
    return "unknown"


def format_duration(ms: float | None) -> str:
    """Format millisecond duration into human-readable string."""
    if ms is None or ms <= 0:
        return "-"
    if ms < 1000:
        return f"{int(ms)}ms"
    return f"{ms / 1000:.1f}s"


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


def collect_snapshot(
    repo_dir: Path,
    explicit_agent: str | None = None,
    duration_ms: float | None = None,
) -> dict[str, Any]:
    """Gather all evaluation metrics for the current repository state."""
    commit = get_git_commit(repo_dir)
    now_iso = datetime.now(UTC).isoformat()
    agent_name = detect_agent(explicit_agent)
    dur_str = format_duration(duration_ms)

    feature_file = repo_dir / "feature_list.json"
    progress_file = repo_dir / "PROGRESS.md"

    feat_lines = count_lines(feature_file)
    prog_lines = count_lines(progress_file)
    feat_tokens = estimate_tokens(feature_file)
    prog_tokens = estimate_tokens(progress_file)
    total_tokens = feat_tokens + prog_tokens

    completed_count = 0
    active_count = 0
    total_count = 0
    archive_refs_count = 0

    if feature_file.is_file():
        try:
            with open(feature_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                archive_refs_count = len(data.get("archive_references", []))
                features = data.get("features", [])
                total_count = len(features)
                for feat in features:
                    status = feat.get("status", "")
                    if status in ("completed", "done"):
                        completed_count += 1
                    elif status in ("in_progress", "in-progress", "active"):
                        active_count += 1
        except (json.JSONDecodeError, OSError):
            pass

    # Count test files in repository
    test_files_count = 0
    scripts_tests_dir = repo_dir / "scripts" / "tests"
    harness_tests_dir = repo_dir / "harness" / "guards" / "tests"
    top_tests_dir = repo_dir / "tests"

    for d in (scripts_tests_dir, harness_tests_dir, top_tests_dir):
        if d.is_dir():
            for p in d.glob("test_*.*"):
                if p.suffix in (".sh", ".py"):
                    test_files_count += 1

    # Threshold checks
    warnings: list[str] = []
    if feat_lines > THRESHOLD_FEATURE_LIST_LINES:
        warnings.append(
            f"feature_list.json exceeds {THRESHOLD_FEATURE_LIST_LINES} lines "
            f"({feat_lines} lines) — archival to docs/archive/features/ recommended."
        )
    if prog_lines > THRESHOLD_PROGRESS_LINES:
        warnings.append(
            f"PROGRESS.md exceeds {THRESHOLD_PROGRESS_LINES} lines "
            f"({prog_lines} lines) — session log pruning recommended."
        )
    if total_tokens > THRESHOLD_STATE_TOKENS:
        warnings.append(
            f"State layer tokens exceed {THRESHOLD_STATE_TOKENS} tokens "
            f"(~{total_tokens:,} tokens) — context bloat detected."
        )

    status_str = "WARN" if warnings else "OK"

    return {
        "commit": commit,
        "timestamp": now_iso,
        "agent": agent_name,
        "duration_ms": duration_ms or 0,
        "duration_str": dur_str,
        "state_layer": {
            "feature_list_lines": feat_lines,
            "feature_list_tokens_est": feat_tokens,
            "progress_lines": prog_lines,
            "progress_tokens_est": prog_tokens,
            "total_state_tokens_est": total_tokens,
            "completed_features": completed_count,
            "active_features": active_count,
            "total_features": total_count,
            "archive_references": archive_refs_count,
        },
        "test_metrics": {
            "test_suites_count": test_files_count,
        },
        "thresholds": {
            "status": status_str,
            "warnings": warnings,
        },
    }


def record_snapshot(
    repo_dir: Path,
    trace_path: Path,
    explicit_agent: str | None = None,
    duration_ms: float | None = None,
) -> dict[str, Any]:
    """Record current snapshot to JSONL file."""
    snapshot = collect_snapshot(
        repo_dir, explicit_agent=explicit_agent, duration_ms=duration_ms
    )
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    with open(trace_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(snapshot) + "\n")
    return snapshot


def render_trend_table(trace_path: Path) -> None:
    """Read trace file and display formatted history table."""
    if not trace_path.is_file():
        print(f"No evaluation trace history found at: {trace_path}")
        return

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

    if not records:
        print(f"No records found in {trace_path}")
        return

    print("=" * 114)
    print(" EVALUATION TRACE HISTORY & MULTI-AGENT STATE EVOLUTION")
    print("=" * 114)
    print(
        f"{'Commit':<10} {'Timestamp':<20} {'Agent':<8} {'Spent Time':<12} "
        f"{'Est. Tokens':<14} {'feat.json':<12} {'prog.md':<10} {'Done (Active)':<14} {'Status':<6}"
    )
    print("-" * 114)

    latest_warnings: list[str] = []
    for rec in records[-15:]:  # Show last 15 entries
        commit = rec.get("commit", "unknown")
        ts = rec.get("timestamp", "")[:19].replace("T", " ")
        ag = rec.get("agent", "unknown")
        dur = rec.get("duration_str") or format_duration(rec.get("duration_ms", 0))
        sl = rec.get("state_layer", {})
        tok = f"~{sl.get('total_state_tokens_est', 0):,} tok"
        feat_l = f"{sl.get('feature_list_lines', 0)} lines"
        prog_l = f"{sl.get('progress_lines', 0)} lines"
        comp = sl.get("completed_features", 0)
        act = sl.get("active_features", 0)
        done_active = f"{comp} ({act} act)"
        st = rec.get("thresholds", {}).get("status", "OK")
        latest_warnings = rec.get("thresholds", {}).get("warnings", [])
        print(
            f"{commit:<10} {ts:<20} {ag:<8} {dur:<12} {tok:<14} "
            f"{feat_l:<12} {prog_l:<10} {done_active:<14} {st:<6}"
        )

    print("=" * 114)
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
            repo_dir, explicit_agent=args.agent, duration_ms=args.duration_ms
        )
        print(json.dumps(snapshot, indent=2))
        return 0

    if args.check_thresholds:
        snapshot = collect_snapshot(
            repo_dir, explicit_agent=args.agent, duration_ms=args.duration_ms
        )
        warnings = snapshot.get("thresholds", {}).get("warnings", [])
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
    )
    print(f"Recorded evaluation trace snapshot to: {target_trace}")
    print(
        f"  Commit: {snapshot['commit']} | Agent: {snapshot['agent']} | "
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
