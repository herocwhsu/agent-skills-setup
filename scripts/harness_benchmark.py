#!/usr/bin/env python3
"""Harness Self-Benchmark Runner.

Executes real commands defined in a benchmark suite, measures execution latencies
across multiple iterations, evaluates SLA compliance, and supports regression
delta comparison between benchmark runs.
"""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


@dataclass
class SuiteTask:
    name: str
    command: str
    sla_target_ms: float
    description: str


@dataclass
class IterationResult:
    iteration: int
    duration_ms: float
    return_code: int
    error: str | None = None


@dataclass
class TaskMetric:
    name: str
    command: str
    sla_target_ms: float
    description: str
    iterations: int
    min_ms: float
    avg_ms: float
    max_ms: float
    p95_ms: float
    sla_passed: bool
    all_success: bool
    runs: list[dict[str, Any]]


@dataclass
class BenchmarkReport:
    version: str
    suite_name: str
    timestamp: str
    git_commit: str
    platform: str
    python_version: str
    sla_threshold_pct: float
    total_duration_ms: float
    tasks_count: int
    passed_sla_count: int
    tasks: dict[str, dict[str, Any]]


def get_git_commit(cwd: Path) -> str:
    try:
        res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode == 0:
            return res.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return "unknown"
    return "unknown"


def load_suite(suite_path: Path) -> tuple[str, float, list[SuiteTask]]:
    if not suite_path.exists():
        raise FileNotFoundError(f"Benchmark suite file not found: {suite_path}")

    with open(suite_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    name = data.get("name", "unnamed-suite")
    sla_thresh = float(data.get("sla_regression_threshold_pct", 15.0))
    raw_tasks = data.get("tasks", [])

    tasks: list[SuiteTask] = []
    for t in raw_tasks:
        tasks.append(
            SuiteTask(
                name=t["name"],
                command=t["command"],
                sla_target_ms=float(t["sla_target_ms"]),
                description=t.get("description", ""),
            )
        )
    return name, sla_thresh, tasks


def run_single_task(
    task: SuiteTask, iterations: int, cwd: Path, quiet: bool = False
) -> TaskMetric:
    runs: list[IterationResult] = []

    for i in range(1, iterations + 1):
        start = time.perf_counter()
        proc = subprocess.run(
            task.command,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        elapsed_ms = (time.perf_counter() - start) * 1000.0

        err_msg = proc.stderr.strip() if proc.returncode != 0 else None
        runs.append(
            IterationResult(
                iteration=i,
                duration_ms=round(elapsed_ms, 2),
                return_code=proc.returncode,
                error=err_msg,
            )
        )
        if not quiet:
            status_tag = "OK" if proc.returncode == 0 else f"ERR({proc.returncode})"
            print(f"    iter {i}/{iterations}: {status_tag} in {elapsed_ms:.1f}ms")

    durations = [r.duration_ms for r in runs]
    durations_sorted = sorted(durations)

    min_ms = round(min(durations), 2)
    avg_ms = round(sum(durations) / len(durations), 2)
    max_ms = round(max(durations), 2)

    # 95th percentile calculation
    p95_idx = round(0.95 * (len(durations_sorted) - 1))
    p95_ms = round(durations_sorted[p95_idx], 2)

    all_success = all(r.return_code == 0 for r in runs)
    sla_passed = all_success and (avg_ms <= task.sla_target_ms)

    return TaskMetric(
        name=task.name,
        command=task.command,
        sla_target_ms=task.sla_target_ms,
        description=task.description,
        iterations=iterations,
        min_ms=min_ms,
        avg_ms=avg_ms,
        max_ms=max_ms,
        p95_ms=p95_ms,
        sla_passed=sla_passed,
        all_success=all_success,
        runs=[asdict(r) for r in runs],
    )


def execute_suite(
    suite_path: Path,
    iterations: int = 3,
    task_filter: str | None = None,
    quiet: bool = False,
    cwd: Path | None = None,
) -> BenchmarkReport:
    workdir = cwd or Path.cwd()
    suite_name, sla_thresh, tasks = load_suite(suite_path)

    if task_filter:
        tasks = [t for t in tasks if t.name == task_filter]
        if not tasks:
            raise ValueError(f"Task '{task_filter}' not found in suite {suite_path}")

    start_total = time.perf_counter()
    metrics: dict[str, dict[str, Any]] = {}
    passed_sla = 0

    if not quiet:
        print("\n=======================================================")
        print(f" Running Harness Benchmark Suite: {suite_name}")
        print(f" Tasks: {len(tasks)} | Iterations: {iterations}")
        print("=======================================================\n")

    for task in tasks:
        if not quiet:
            print(f"--> [{task.name}] (SLA: {task.sla_target_ms:.0f}ms)")
            print(f"    cmd: {task.command}")

        m = run_single_task(task, iterations=iterations, cwd=workdir, quiet=quiet)
        metrics[task.name] = asdict(m)

        if m.sla_passed:
            passed_sla += 1

        if not quiet:
            sla_tag = "PASS" if m.sla_passed else "FAIL"
            print(
                f"    result: {sla_tag} (avg: {m.avg_ms:.1f}ms, min: {m.min_ms:.1f}ms, "
                f"max: {m.max_ms:.1f}ms, p95: {m.p95_ms:.1f}ms)\n"
            )

    total_duration_ms = round((time.perf_counter() - start_total) * 1000.0, 2)

    report = BenchmarkReport(
        version="1.0.0",
        suite_name=suite_name,
        timestamp=datetime.now(UTC).isoformat(),
        git_commit=get_git_commit(workdir),
        platform=platform.platform(),
        python_version=platform.python_version(),
        sla_threshold_pct=sla_thresh,
        total_duration_ms=total_duration_ms,
        tasks_count=len(tasks),
        passed_sla_count=passed_sla,
        tasks=metrics,
    )
    return report


def print_summary_table(report: BenchmarkReport) -> None:
    print("\n" + "=" * 80)
    print(f" BENCHMARK SUMMARY: {report.suite_name}")
    print(f" Commit: {report.git_commit[:10]} | Platform: {report.platform}")
    print("=" * 80)
    print(f"{'Task':<26} {'SLA Budget':<12} {'Avg Latency':<14} {'p95 Latency':<14} {'Status':<8}")
    print("-" * 80)

    for name, t in report.tasks.items():
        status = "PASS" if t["sla_passed"] else "FAIL"
        sla_str = f"{t['sla_target_ms']:.0f}ms"
        avg_str = f"{t['avg_ms']:.1f}ms"
        p95_str = f"{t['p95_ms']:.1f}ms"
        print(f"{name:<26} {sla_str:<12} {avg_str:<14} {p95_str:<14} {status:<8}")

    print("-" * 80)
    pass_pct = (report.passed_sla_count / report.tasks_count * 100.0) if report.tasks_count else 0.0
    print(
        f"Total: {report.passed_sla_count}/{report.tasks_count} tasks met SLA "
        f"({pass_pct:.1f}%) in {report.total_duration_ms:.0f}ms\n"
    )


def compare_reports(
    baseline_path: Path, candidate_path: Path, threshold_pct: float | None = None
) -> int:
    with open(baseline_path, "r", encoding="utf-8") as f:
        b_data = json.load(f)
    with open(candidate_path, "r", encoding="utf-8") as f:
        c_data = json.load(f)

    thresh = threshold_pct if threshold_pct is not None else float(c_data.get("sla_threshold_pct", 15.0))

    b_tasks: dict[str, Any] = b_data.get("tasks", {})
    c_tasks: dict[str, Any] = c_data.get("tasks", {})

    all_keys = sorted(set(b_tasks.keys()).union(set(c_tasks.keys())))

    print("\n" + "=" * 90)
    print(" BENCHMARK DELTA COMPARISON: Baseline vs Candidate")
    print(f" Baseline commit : {b_data.get('git_commit', 'unknown')[:10]}")
    print(f" Candidate commit: {c_data.get('git_commit', 'unknown')[:10]}")
    print(f" Regression limit: +{thresh:.1f}%")
    print("=" * 90)
    print(f"{'Task':<24} {'Baseline':<12} {'Candidate':<12} {'Delta (ms)':<14} {'Delta (%)':<12} {'Verdict':<12}")
    print("-" * 90)

    regressions = 0
    sla_breaches = 0

    for k in all_keys:
        if k not in b_tasks:
            print(f"{k:<24} {'[N/A]':<12} {c_tasks[k]['avg_ms']:<12.1f} {'--':<14} {'--':<12} {'[NEW]':<12}")
            continue
        if k not in c_tasks:
            print(f"{k:<24} {b_tasks[k]['avg_ms']:<12.1f} {'[REMOVED]':<12} {'--':<14} {'--':<12} {'[DROPPED]':<12}")
            continue

        b_avg = float(b_tasks[k]["avg_ms"])
        c_avg = float(c_tasks[k]["avg_ms"])
        sla = float(c_tasks[k]["sla_target_ms"])

        delta_ms = c_avg - b_avg
        delta_pct = (delta_ms / b_avg * 100.0) if b_avg > 0 else 0.0

        is_regression = (delta_pct > thresh) and (delta_ms > 30.0)
        is_sla_breach = c_avg > sla

        if is_sla_breach:
            verdict = "[SLA BREACH]"
            sla_breaches += 1
        elif is_regression:
            verdict = "[REGRESSION]"
            regressions += 1
        elif delta_pct < -5.0 and delta_ms < -30.0:
            verdict = "[IMPROVED]"
        else:
            verdict = "[STABLE]"

        delta_sign = "+" if delta_ms > 0 else ""
        delta_ms_str = f"{delta_sign}{delta_ms:.1f}ms"
        delta_pct_str = f"{delta_sign}{delta_pct:.1f}%"

        print(f"{k:<24} {b_avg:<12.1f} {c_avg:<12.1f} {delta_ms_str:<14} {delta_pct_str:<12} {verdict:<12}")

    print("-" * 90)
    print(f"Summary: {regressions} regressions, {sla_breaches} SLA breaches detected.\n")

    if regressions > 0 or sla_breaches > 0:
        return 1
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Production harness self-benchmark runner and regression tracker."
    )
    parser.add_argument(
        "--suite",
        type=Path,
        default=Path("benchmarks/harness-suite.json"),
        help="Path to benchmark suite JSON (default: benchmarks/harness-suite.json)",
    )
    parser.add_argument(
        "-n",
        "--iterations",
        type=int,
        default=3,
        help="Number of iterations per benchmark task (default: 3)",
    )
    parser.add_argument(
        "--task",
        type=str,
        default=None,
        help="Execute a specific task only by name",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Save report results to target JSON file",
    )
    parser.add_argument(
        "--compare",
        nargs=2,
        metavar=("BASELINE", "CANDIDATE"),
        help="Compare two benchmark JSON result files and evaluate regressions",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=None,
        help="Custom regression threshold percentage for comparison mode",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress per-iteration verbose execution logs",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    if args.compare:
        baseline_file = Path(args.compare[0])
        candidate_file = Path(args.compare[1])
        return compare_reports(
            baseline_file, candidate_file, threshold_pct=args.threshold
        )

    try:
        report = execute_suite(
            suite_path=args.suite,
            iterations=args.iterations,
            task_filter=args.task,
            quiet=args.quiet,
        )
    except (ValueError, FileNotFoundError, json.JSONDecodeError, OSError) as e:
        print(f"Error executing benchmark suite: {e}", file=sys.stderr)
        return 2

    print_summary_table(report)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(asdict(report), f, indent=2)
        print(f"Benchmark results written to: {args.output}")

    if report.passed_sla_count == report.tasks_count:
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
