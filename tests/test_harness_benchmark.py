import json
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from harness_benchmark import (
    SuiteTask,
    compare_reports,
    execute_suite,
    load_suite,
    main,
    run_single_task,
)


@pytest.fixture
def sample_suite_file(tmp_path: Path) -> Path:
    suite_data = {
        "version": "1.0.0",
        "name": "test-suite",
        "sla_regression_threshold_pct": 20.0,
        "tasks": [
            {
                "name": "fast_echo",
                "command": "echo 'benchmark fast'",
                "sla_target_ms": 500.0,
                "description": "Fast echo command",
            },
            {
                "name": "second_echo",
                "command": "echo 'second task'",
                "sla_target_ms": 600.0,
                "description": "Second echo task",
            },
        ],
    }
    p = tmp_path / "test-suite.json"
    with open(p, "w", encoding="utf-8") as f:
        json.dump(suite_data, f)
    return p


def test_load_suite_valid(sample_suite_file: Path) -> None:
    name, thresh, tasks = load_suite(sample_suite_file)
    assert name == "test-suite"
    assert thresh == 20.0
    assert len(tasks) == 2
    assert tasks[0].name == "fast_echo"
    assert tasks[0].sla_target_ms == 500.0


def test_load_suite_missing(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError):
        load_suite(tmp_path / "non-existent.json")


def test_run_single_task_success(tmp_path: Path) -> None:
    task = SuiteTask(
        name="echo_test",
        command="echo hello",
        sla_target_ms=1000.0,
        description="Echo test",
    )
    metric = run_single_task(task, iterations=3, cwd=tmp_path, quiet=True)
    assert metric.name == "echo_test"
    assert metric.iterations == 3
    assert metric.all_success is True
    assert metric.sla_passed is True
    assert metric.min_ms <= metric.avg_ms <= metric.max_ms
    assert len(metric.runs) == 3


def test_run_single_task_failure(tmp_path: Path) -> None:
    task = SuiteTask(
        name="fail_test",
        command="exit 1",
        sla_target_ms=1000.0,
        description="Failing test",
    )
    metric = run_single_task(task, iterations=2, cwd=tmp_path, quiet=True)
    assert metric.all_success is False
    assert metric.sla_passed is False
    assert metric.runs[0]["return_code"] == 1


def test_execute_suite_with_filter(sample_suite_file: Path, tmp_path: Path) -> None:
    report = execute_suite(
        suite_path=sample_suite_file,
        iterations=2,
        task_filter="fast_echo",
        quiet=True,
        cwd=tmp_path,
    )
    assert report.suite_name == "test-suite"
    assert report.tasks_count == 1
    assert "fast_echo" in report.tasks
    assert "second_echo" not in report.tasks
    assert report.passed_sla_count == 1


def test_compare_reports_stable(tmp_path: Path) -> None:
    base_data: dict[str, Any] = {
        "git_commit": "abc1234",
        "sla_threshold_pct": 15.0,
        "tasks": {
            "task_a": {"avg_ms": 100.0, "sla_target_ms": 200.0},
        },
    }
    cand_data: dict[str, Any] = {
        "git_commit": "def5678",
        "sla_threshold_pct": 15.0,
        "tasks": {
            "task_a": {"avg_ms": 105.0, "sla_target_ms": 200.0},
        },
    }
    b_file = tmp_path / "base.json"
    c_file = tmp_path / "cand.json"
    b_file.write_text(json.dumps(base_data))
    c_file.write_text(json.dumps(cand_data))

    code = compare_reports(b_file, c_file)
    assert code == 0


def test_compare_reports_regression(tmp_path: Path) -> None:
    base_data: dict[str, Any] = {
        "git_commit": "abc1234",
        "sla_threshold_pct": 15.0,
        "tasks": {
            "task_a": {"avg_ms": 100.0, "sla_target_ms": 500.0},
        },
    }
    # 100ms -> 200ms is +100% and >30ms -> regression!
    cand_data: dict[str, Any] = {
        "git_commit": "def5678",
        "sla_threshold_pct": 15.0,
        "tasks": {
            "task_a": {"avg_ms": 200.0, "sla_target_ms": 500.0},
        },
    }
    b_file = tmp_path / "base.json"
    c_file = tmp_path / "cand.json"
    b_file.write_text(json.dumps(base_data))
    c_file.write_text(json.dumps(cand_data))

    code = compare_reports(b_file, c_file)
    assert code == 1


def test_compare_reports_sla_breach(tmp_path: Path) -> None:
    base_data: dict[str, Any] = {
        "git_commit": "abc1234",
        "sla_threshold_pct": 15.0,
        "tasks": {
            "task_a": {"avg_ms": 180.0, "sla_target_ms": 200.0},
        },
    }
    # 250ms breaches SLA 200ms
    cand_data: dict[str, Any] = {
        "git_commit": "def5678",
        "sla_threshold_pct": 15.0,
        "tasks": {
            "task_a": {"avg_ms": 250.0, "sla_target_ms": 200.0},
        },
    }
    b_file = tmp_path / "base.json"
    c_file = tmp_path / "cand.json"
    b_file.write_text(json.dumps(base_data))
    c_file.write_text(json.dumps(cand_data))

    code = compare_reports(b_file, c_file)
    assert code == 1


def test_cli_execution_and_output(sample_suite_file: Path, tmp_path: Path) -> None:
    out_file = tmp_path / "out.json"
    ret = main(
        [
            "--suite",
            str(sample_suite_file),
            "-n",
            "1",
            "--task",
            "fast_echo",
            "-o",
            str(out_file),
            "--quiet",
        ]
    )
    assert ret == 0
    assert out_file.exists()
    data = json.loads(out_file.read_text(encoding="utf-8"))
    assert data["tasks_count"] == 1
    assert "fast_echo" in data["tasks"]


def test_shell_wrapper_help() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    cmd = ["bash", str(repo_root / "scripts" / "harness-benchmark.sh"), "--help"]
    res = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, check=False)
    assert res.returncode == 0
    assert "Production harness self-benchmark runner" in res.stdout
