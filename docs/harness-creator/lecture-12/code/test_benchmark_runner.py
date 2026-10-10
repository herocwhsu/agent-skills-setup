"""Tests for benchmark_runner.py."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from benchmark_runner import (
    BenchmarkTask,
    compare_benchmarks,
    execute_benchmark,
    format_benchmark_report,
    load_benchmark_tasks,
    main,
)


def test_load_default_benchmark_tasks():
    tasks = load_benchmark_tasks()
    assert len(tasks) == 8
    assert tasks[0].id == "bench-001"
    assert tasks[0].actual_pass is True
    assert tasks[1].actual_pass is False


def test_load_benchmark_tasks_from_file(tmp_path: Path):
    custom_tasks = [
        {
            "id": "custom-1",
            "name": "Custom Task",
            "category": "Custom",
            "pass_criteria": ["Criteria 1", "Criteria 2"],
            "expected_duration_ms": 150.0,
            "actual_duration_ms": 140.0,
            "actual_pass": True,
        }
    ]
    file_path = tmp_path / "benchmarks.json"
    file_path.write_text(json.dumps(custom_tasks), encoding="utf-8")

    loaded = load_benchmark_tasks(file_path)
    assert len(loaded) == 1
    assert loaded[0].id == "custom-1"
    assert loaded[0].expected_duration_ms == 150.0


def test_execute_benchmark():
    tasks = [
        BenchmarkTask(
            id="t1",
            name="Pass Task",
            category="CatA",
            pass_criteria=["c1", "c2"],
            expected_duration_ms=100.0,
            actual_duration_ms=110.0,
            actual_pass=True,
        ),
        BenchmarkTask(
            id="t2",
            name="Fail Task",
            category="CatB",
            pass_criteria=["c1", "c2", "c3", "c4"],
            expected_duration_ms=200.0,
            actual_duration_ms=250.0,
            actual_pass=False,
            failure_reason="Timeout",
        ),
    ]

    results = execute_benchmark(tasks)
    assert len(results) == 2

    r1 = results[0]
    assert r1.pass_status is True
    assert r1.criteria_passed == 2
    assert r1.duration_delta_ms == 10.0

    r2 = results[1]
    assert r2.pass_status is False
    assert r2.criteria_passed == 2
    assert r2.duration_delta_ms == 50.0
    assert r2.failure_reason == "Timeout"


def test_compare_benchmarks():
    tasks_a = [
        BenchmarkTask("t1", "Task 1", "Cat", ["c1"], 100, 100, True),
        BenchmarkTask("t2", "Task 2", "Cat", ["c1"], 100, 100, False),
        BenchmarkTask("t4", "Task 4", "Cat", ["c1"], 100, 100, True),  # Will be removed in B
    ]
    tasks_b = [
        BenchmarkTask("t1", "Task 1", "Cat", ["c1"], 100, 90, True),
        BenchmarkTask("t2", "Task 2", "Cat", ["c1"], 100, 95, True),   # Improvement
        BenchmarkTask("t3", "Task 3", "Cat", ["c1"], 100, 150, False), # New failing task -> regression
    ]

    res_a = execute_benchmark(tasks_a)
    res_b = execute_benchmark(tasks_b)

    diff = compare_benchmarks(res_a, res_b)
    assert diff["harness_a"]["completion_rate"] == 66.7
    assert diff["harness_b"]["completion_rate"] == 66.7
    assert "t2" in diff["improvements"]
    assert "t3" in diff["regressions"]
    assert "t4" in diff["regressions"]
    assert "t3" in diff["new_tasks"]
    assert "t4" in diff["removed_tasks"]


def test_format_benchmark_report():
    tasks = load_benchmark_tasks()
    results = execute_benchmark(tasks)
    report = format_benchmark_report(results)

    assert "BENCHMARK RUNNER -- Task Execution Report" in report
    assert "bench-001" in report
    assert "FAILURE DETAILS" in report
    assert "SUMMARY BY CATEGORY" in report
    assert "OVERALL: 5/8 passed (62%), 3 failures" in report


def test_cli_execution_with_default(capsys: pytest.CaptureFixture[str]):
    rc = main([])
    assert rc == 1  # Fails because default tasks have failures
    captured = capsys.readouterr()
    assert "BENCHMARK RUNNER" in captured.out


def test_cli_execution_json(capsys: pytest.CaptureFixture[str]):
    rc = main(["--json"])
    assert rc == 1
    captured = capsys.readouterr()
    data = json.loads(captured.out)
    assert data["total"] == 8
    assert data["passed"] == 5


def test_cli_compare(tmp_path: Path, capsys: pytest.CaptureFixture[str]):
    t1 = [{"id": "t1", "name": "T1", "category": "C", "pass_criteria": ["c1"], "expected_duration_ms": 100, "actual_duration_ms": 100, "actual_pass": True}]
    t2 = [{"id": "t1", "name": "T1", "category": "C", "pass_criteria": ["c1"], "expected_duration_ms": 100, "actual_duration_ms": 100, "actual_pass": False}]

    f1 = tmp_path / "a.json"
    f2 = tmp_path / "b.json"
    f1.write_text(json.dumps(t1), encoding="utf-8")
    f2.write_text(json.dumps(t2), encoding="utf-8")

    rc = main(["--compare", str(f1), str(f2)])
    assert rc == 0
    captured = capsys.readouterr()
    diff = json.loads(captured.out)
    assert diff["regressions"] == ["t1"]


def test_cli_file_not_found(capsys: pytest.CaptureFixture[str]):
    rc = main(["--file", "/nonexistent/bench.json"])
    assert rc == 2
    captured = capsys.readouterr()
    assert "Error: Benchmark file not found" in captured.err
