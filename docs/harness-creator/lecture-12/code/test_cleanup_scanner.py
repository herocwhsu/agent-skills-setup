"""Tests for cleanup_scanner.py."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from cleanup_scanner import (
    default_checks,
    find_files_with_extensions,
    format_scan_report,
    main,
    run_cleanup_scan,
    scan_for_patterns,
)


@pytest.fixture
def clean_project(tmp_path: Path) -> Path:
    proj = tmp_path / "clean_proj"
    proj.mkdir()
    (proj / ".gitignore").write_text("node_modules/\n.venv/\n")
    src = proj / "src"
    src.mkdir()
    (src / "app.py").write_text("def hello(): return 'world'\n")
    return proj


def test_find_files_with_extensions(tmp_path: Path):
    (tmp_path / "file1.tmp").write_text("temp")
    (tmp_path / "file2.bak").write_text("backup")
    (tmp_path / "file3.py").write_text("code")

    ignored = tmp_path / "node_modules"
    ignored.mkdir()
    (ignored / "leak.tmp").write_text("leak")

    found = find_files_with_extensions(tmp_path, (".tmp", ".bak"))
    assert found == ["file1.tmp", "file2.bak"]


def test_scan_for_patterns(tmp_path: Path):
    src = tmp_path / "src"
    src.mkdir()
    (src / "code.py").write_text("# TODO: fix later\n# FIXME: urgent\nx = 1\n")
    found = scan_for_patterns(tmp_path, src, ["TODO:", "FIXME:"])
    assert len(found) == 2
    assert "src/code.py:1 contains TODO:" in found[0]
    assert "src/code.py:2 contains FIXME:" in found[1]


def test_clean_project_scan(clean_project: Path):
    results = run_cleanup_scan(clean_project)
    assert len(results) == len(default_checks())
    total_found = sum(len(r.found) for r in results)
    assert total_found == 0
    report = format_scan_report(results, clean_project)
    assert "Project is in a clean state" in report


def test_detects_stale_artifacts(clean_project: Path):
    (clean_project / "scratch.tmp").write_text("leftover")
    src = clean_project / "src"
    (src / "debug.log").write_text("log output")

    results = run_cleanup_scan(clean_project)
    tmp_check = next(r for r in results if "Temporary files" in r.check)
    assert "scratch.tmp" in tmp_check.found

    log_check = next(r for r in results if "Debug/log files" in r.check)
    assert "src/debug.log" in log_check.found


def test_detects_missing_gitignore(tmp_path: Path):
    proj = tmp_path / "no_git"
    proj.mkdir()
    results = run_cleanup_scan(proj)
    git_check = next(r for r in results if "Missing .gitignore" in r.check)
    assert ".gitignore (MISSING)" in git_check.found


def test_detects_build_artifacts_and_nested_node_modules(clean_project: Path):
    nested_dist = clean_project / "src" / "dist"
    nested_dist.mkdir()
    nested_nm = clean_project / "src" / "node_modules"
    nested_nm.mkdir()

    results = run_cleanup_scan(clean_project)
    dist_check = next(r for r in results if "Build artifacts" in r.check)
    assert "src/dist" in dist_check.found

    nm_check = next(r for r in results if "node_modules in source" in r.check)
    assert "src/node_modules/" in nm_check.found


def test_detects_wip_markers_and_env_files(clean_project: Path):
    (clean_project / "WIP.md").write_text("Work in progress")
    (clean_project / "scratch.py").write_text("scratch script")
    (clean_project / ".env.local").write_text("SECRET_KEY=123")

    results = run_cleanup_scan(clean_project)
    wip_check = next(r for r in results if "Uncommitted WIP" in r.check)
    assert "WIP.md" in wip_check.found
    assert "scratch.py" in wip_check.found

    env_check = next(r for r in results if "Environment files" in r.check)
    assert ".env.local" in env_check.found
    assert env_check.severity == "critical"


def test_cli_execution_and_json_flag(clean_project: Path, capsys: pytest.CaptureFixture[str]):
    (clean_project / "temp.bak").write_text("backup")
    rc = main([str(clean_project), "--json"])
    assert rc == 0
    captured = capsys.readouterr()
    data = json.loads(captured.out)
    assert data["total_issues"] >= 1
    assert any("temp.bak" in r["found"] for r in data["results"])


def test_cli_returns_1_on_critical_violation(clean_project: Path):
    (clean_project / ".env").write_text("API_KEY=leak")
    rc = main([str(clean_project)])
    assert rc == 1


def test_cli_nonexistent_path(capsys: pytest.CaptureFixture[str]):
    rc = main(["/nonexistent/directory/path/12345"])
    assert rc == 2
    captured = capsys.readouterr()
    assert "Target path does not exist" in captured.err


def test_detects_empty_directories(clean_project: Path):
    empty_sub = clean_project / "src" / "empty_feature"
    empty_sub.mkdir()
    results = run_cleanup_scan(clean_project)
    empty_check = next(r for r in results if "Empty directories" in r.check)
    assert any("src/empty_feature/" in f for f in empty_check.found)


def test_deep_nested_and_past_100_lines(clean_project: Path):
    deep_dir = clean_project / "src" / "l1" / "l2" / "l3" / "l4" / "l5"
    deep_dir.mkdir(parents=True)
    (deep_dir / "deep.tmp").write_text("deep temp")

    long_file = clean_project / "src" / "long.py"
    lines = ["# line\n"] * 120 + ["# FIXME: debt on line 121\n"]
    long_file.write_text("".join(lines))

    results = run_cleanup_scan(clean_project)
    tmp_check = next(r for r in results if "Temporary files" in r.check)
    assert any("deep.tmp" in f for f in tmp_check.found)

    debt_check = next(r for r in results if "Unfinished code markers" in r.check)
    assert any("src/long.py:121 contains FIXME:" in f for f in debt_check.found)


def test_cli_strict_fails_on_warnings(clean_project: Path):
    (clean_project / "stray.bak").write_text("backup")
    assert main([str(clean_project)]) == 0
    assert main([str(clean_project), "--strict"]) == 1

