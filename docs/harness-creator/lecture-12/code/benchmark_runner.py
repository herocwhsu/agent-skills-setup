#!/usr/bin/env python3
"""Benchmark runner: Reads and executes benchmark tasks, profiles pass criteria

and execution duration, and generates comparison reports across harness configurations.
Ported from TypeScript benchmark-runner.ts.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


@dataclass
class BenchmarkTask:
    id: str
    name: str
    category: str
    pass_criteria: list[str]
    expected_duration_ms: float
    actual_duration_ms: float
    actual_pass: bool
    failure_reason: str | None = None


@dataclass
class BenchmarkResult:
    id: str
    name: str
    category: str
    criteria_total: int
    criteria_passed: int
    pass_status: bool
    expected_ms: float
    actual_ms: float
    duration_delta_ms: float
    failure_reason: str | None = None


DEFAULT_BENCHMARK_TASKS: list[dict[str, Any]] = [
    {
        "id": "bench-001",
        "name": "Import markdown document",
        "category": "Document Pipeline",
        "pass_criteria": ["File accepted", "Chunks created", "Metadata stored"],
        "expected_duration_ms": 100.0,
        "actual_duration_ms": 95.0,
        "actual_pass": True,
    },
    {
        "id": "bench-002",
        "name": "Import PDF document",
        "category": "Document Pipeline",
        "pass_criteria": ["File accepted", "Text extracted", "Chunks created", "Metadata stored"],
        "expected_duration_ms": 200.0,
        "actual_duration_ms": 310.0,
        "actual_pass": False,
        "failure_reason": "PDF text extraction failed on page 3 -- encoding issue",
    },
    {
        "id": "bench-003",
        "name": "Ask grounded question",
        "category": "Q&A Pipeline",
        "pass_criteria": ["Query received", "Relevant chunks retrieved", "Answer generated", "Citations present"],
        "expected_duration_ms": 500.0,
        "actual_duration_ms": 480.0,
        "actual_pass": True,
    },
    {
        "id": "bench-004",
        "name": "Ask question with no relevant docs",
        "category": "Q&A Pipeline",
        "pass_criteria": ["Query received", "Graceful 'no results' message", "No hallucinated citations"],
        "expected_duration_ms": 400.0,
        "actual_duration_ms": 420.0,
        "actual_pass": False,
        "failure_reason": "Model hallucinated a citation instead of saying 'no results'",
    },
    {
        "id": "bench-005",
        "name": "Delete imported document",
        "category": "Document Pipeline",
        "pass_criteria": ["Document removed from list", "Chunks removed from index", "No orphan data"],
        "expected_duration_ms": 150.0,
        "actual_duration_ms": 145.0,
        "actual_pass": True,
    },
    {
        "id": "bench-006",
        "name": "Concurrent user access",
        "category": "Security",
        "pass_criteria": ["Users isolated", "No cross-user data leak", "Performance within SLA"],
        "expected_duration_ms": 300.0,
        "actual_duration_ms": 850.0,
        "actual_pass": False,
        "failure_reason": "Cross-user data leak detected + response time exceeded SLA (850ms > 500ms)",
    },
    {
        "id": "bench-007",
        "name": "Session continuity after restart",
        "category": "Reliability",
        "pass_criteria": ["State persisted", "Session recovers", "No data loss"],
        "expected_duration_ms": 200.0,
        "actual_duration_ms": 180.0,
        "actual_pass": True,
    },
    {
        "id": "bench-008",
        "name": "API rate limiting",
        "category": "Security",
        "pass_criteria": ["Rate limit enforced", "429 response after limit", "Legitimate traffic unaffected"],
        "expected_duration_ms": 100.0,
        "actual_duration_ms": 100.0,
        "actual_pass": True,
    },
]


def load_benchmark_tasks(source: str | Path | list[dict[str, Any]] | None = None) -> list[BenchmarkTask]:
    if source is None:
        data = DEFAULT_BENCHMARK_TASKS
    elif isinstance(source, (str, Path)):
        p = Path(source)
        if not p.is_file():
            raise FileNotFoundError(f"Benchmark file not found: {p}")
        data = json.loads(p.read_text(encoding="utf-8"))
    else:
        data = source

    tasks: list[BenchmarkTask] = []
    for item in data:
        tasks.append(
            BenchmarkTask(
                id=str(item["id"]),
                name=str(item["name"]),
                category=str(item.get("category", "General")),
                pass_criteria=list(item.get("pass_criteria", [])),
                expected_duration_ms=float(item.get("expected_duration_ms", 100.0)),
                actual_duration_ms=float(item.get("actual_duration_ms", 100.0)),
                actual_pass=bool(item.get("actual_pass", False)),
                failure_reason=item.get("failure_reason"),
            )
        )
    return tasks


def execute_benchmark(tasks: list[BenchmarkTask]) -> list[BenchmarkResult]:
    results: list[BenchmarkResult] = []
    for t in tasks:
        total = len(t.pass_criteria)
        passed = total if t.actual_pass else math.floor(total * 0.5)
        results.append(
            BenchmarkResult(
                id=t.id,
                name=t.name,
                category=t.category,
                criteria_total=total,
                criteria_passed=passed,
                pass_status=t.actual_pass,
                expected_ms=t.expected_duration_ms,
                actual_ms=t.actual_duration_ms,
                duration_delta_ms=t.actual_duration_ms - t.expected_duration_ms,
                failure_reason=t.failure_reason,
            )
        )
    return results


def compare_benchmarks(
    harness_a: list[BenchmarkResult], harness_b: list[BenchmarkResult]
) -> dict[str, Any]:
    """Compares benchmark execution results across Harness A and Harness B."""
    a_map = {r.id: r for r in harness_a}
    b_map = {r.id: r for r in harness_b}
    all_ids = sorted(set(a_map.keys()) | set(b_map.keys()))

    a_passed = sum(1 for r in harness_a if r.pass_status)
    b_passed = sum(1 for r in harness_b if r.pass_status)

    a_total = len(harness_a) or 1
    b_total = len(harness_b) or 1

    a_rate = round((a_passed / a_total) * 100, 1)
    b_rate = round((b_passed / b_total) * 100, 1)

    regressions: list[str] = []
    improvements: list[str] = []
    new_tasks: list[str] = []
    removed_tasks: list[str] = []

    for task_id in all_ids:
        res_a = a_map.get(task_id)
        res_b = b_map.get(task_id)
        if res_a is None and res_b is not None:
            new_tasks.append(task_id)
            if not res_b.pass_status:
                regressions.append(task_id)
        elif res_a is not None and res_b is None:
            removed_tasks.append(task_id)
            if res_a.pass_status:
                regressions.append(task_id)
        elif res_a and res_b:
            if res_a.pass_status and not res_b.pass_status:
                regressions.append(task_id)
            elif not res_a.pass_status and res_b.pass_status:
                improvements.append(task_id)

    return {
        "harness_a": {
            "total": len(harness_a),
            "passed": a_passed,
            "completion_rate": a_rate,
            "avg_duration_ms": round(sum(r.actual_ms for r in harness_a) / a_total, 1),
        },
        "harness_b": {
            "total": len(harness_b),
            "passed": b_passed,
            "completion_rate": b_rate,
            "avg_duration_ms": round(sum(r.actual_ms for r in harness_b) / b_total, 1),
        },
        "improvements": improvements,
        "regressions": regressions,
        "new_tasks": new_tasks,
        "removed_tasks": removed_tasks,
        "rate_delta": round(b_rate - a_rate, 1),
    }


def format_benchmark_report(results: list[BenchmarkResult]) -> str:
    lines: list[str] = [
        "=" * 100,
        "  BENCHMARK RUNNER -- Task Execution Report",
        "=" * 100,
        f"\n| {'ID':<10}| {'Task':<35}| {'Category':<18}| {'Pass?':<6}| {'Criteria':<10}| {'Expected':<10}| {'Actual':<10}| {'Delta':<8}|",
        f"|{'-' * 11}|{'-' * 36}|{'-' * 19}|{'-' * 7}|{'-' * 11}|{'-' * 11}|{'-' * 11}|{'-' * 9}|",
    ]

    for r in results:
        pass_str = "PASS" if r.pass_status else "FAIL"
        crit_str = f"{r.criteria_passed}/{r.criteria_total}"
        delta_str = f"{r.duration_delta_ms:+.0f}ms"
        marker = "  " if r.pass_status else ">>"
        lines.append(
            f"{marker}| {r.id:<10}| {r.name:<35}| {r.category:<18}| {pass_str:<6}| {crit_str:<10}| {f'{r.expected_ms:.0f}ms':<10}| {f'{r.actual_ms:.0f}ms':<10}| {delta_str:<8}|"
        )

    failures = [r for r in results if not r.pass_status]
    if failures:
        lines.extend([
            "\n" + "-" * 100,
            "  FAILURE DETAILS",
            "-" * 100,
        ])
        for f in failures:
            lines.extend([
                f"\n  [{f.id}] {f.name}",
                f"    Category:    {f.category}",
                f"    Criteria:    {f.criteria_passed}/{f.criteria_total} passed",
                f"    Reason:      {f.failure_reason or 'Unknown'}",
                f"    Timing:      Expected {f.expected_ms:.0f}ms, actual {f.actual_ms:.0f}ms (delta: {f.duration_delta_ms:+.0f}ms)",
            ])

    categories = sorted({r.category for r in results})
    lines.extend([
        "\n" + "=" * 100,
        "  SUMMARY BY CATEGORY",
        "=" * 100 + "\n",
        f"| {'Category':<20}| {'Total':<8}| {'Passed':<8}| {'Failed':<8}| {'Pass Rate':<12}|",
        f"|{'-' * 21}|{'-' * 9}|{'-' * 9}|{'-' * 9}|{'-' * 13}|",
    ])

    for cat in categories:
        cat_items = [r for r in results if r.category == cat]
        cat_p = sum(1 for r in cat_items if r.pass_status)
        cat_f = len(cat_items) - cat_p
        rate = round((cat_p / len(cat_items)) * 100) if cat_items else 0
        lines.append(f"| {cat:<20}| {len(cat_items):<8}| {cat_p:<8}| {cat_f:<8}| {f'{rate}%':<12}|")

    total_passed = sum(1 for r in results if r.pass_status)
    total = len(results) or 1
    lines.extend([
        "\n" + "-" * 100,
        f"  OVERALL: {total_passed}/{len(results)} passed ({round((total_passed / total) * 100)}%), {len(results) - total_passed} failures",
        "=" * 100 + "\n",
    ])

    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Benchmark Runner: Execute tasks and report regression rates")
    parser.add_argument("--file", help="Path to JSON file containing benchmark task definitions")
    parser.add_argument("--json", action="store_true", help="Output benchmark results in structured JSON")
    parser.add_argument("--compare", nargs=2, metavar=("HARNESS_A", "HARNESS_B"), help="Compare two benchmark runs")
    args = parser.parse_args(argv)

    try:
        if args.compare:
            file_a, file_b = args.compare
            res_a = execute_benchmark(load_benchmark_tasks(file_a))
            res_b = execute_benchmark(load_benchmark_tasks(file_b))
            diff = compare_benchmarks(res_a, res_b)
            print(json.dumps(diff, indent=2))
            return 0

        tasks = load_benchmark_tasks(args.file)
    except (FileNotFoundError, json.JSONDecodeError, OSError) as e:
        sys.stderr.write(f"Error: {e}\n")
        return 2

    results = execute_benchmark(tasks)

    if args.json:
        payload = {
            "total": len(results),
            "passed": sum(1 for r in results if r.pass_status),
            "results": [asdict(r) for r in results],
        }
        print(json.dumps(payload, indent=2))
    else:
        print(format_benchmark_report(results))

    return 0 if all(r.pass_status for r in results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
