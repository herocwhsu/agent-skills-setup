"""Unit tests for the Lecture 03 repo reader."""

from pathlib import Path

from repo_reader import MAX_SCORE, grade, score_repo


def _touch(root: Path, *rels: str) -> None:
    for rel in rels:
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("x", encoding="utf-8")


def test_empty_repo_scores_zero_and_grades_f(tmp_path: Path) -> None:
    result = score_repo(tmp_path)
    assert result["total"] == 0
    assert result["max"] == MAX_SCORE == 100
    assert grade(result["total"]).startswith("F")


def test_full_repo_scores_100_and_grades_a(tmp_path: Path) -> None:
    _touch(
        tmp_path,
        "AGENTS.md",
        "docs/architecture.md",
        "feature_list.json",
        "PROGRESS.md",
        "tests/test_x.py",
        "pyproject.toml",
        "README.md",
    )
    result = score_repo(tmp_path)
    assert result["total"] == 100
    assert grade(result["total"]).startswith("A")


def test_missing_criterion_loses_only_its_points(tmp_path: Path) -> None:
    _touch(tmp_path, "AGENTS.md", "README.md")
    result = score_repo(tmp_path)
    assert result["total"] == 25
    failed = [c["name"] for c in result["checks"] if c["points"] == 0]
    assert "Feature tracking" in failed
    assert "AGENTS.md / CLAUDE.md" not in failed


def test_directory_criteria_ignore_plain_files(tmp_path: Path) -> None:
    _touch(tmp_path, "docs", "tests")
    result = score_repo(tmp_path)
    by_name = {c["name"]: c["points"] for c in result["checks"]}
    assert by_name["Documentation directory"] == 0
    assert by_name["Testing structure"] == 0


def test_grade_boundaries() -> None:
    assert grade(90).startswith("A")
    assert grade(89).startswith("B")
    assert grade(70).startswith("B")
    assert grade(69).startswith("C")
    assert grade(50).startswith("C")
    assert grade(49).startswith("D")
    assert grade(30).startswith("D")
    assert grade(29).startswith("F")
