"""Unit tests for the Lecture 08 feature list validator."""

import json
from pathlib import Path

import pytest

from feature_list_validator import load_features, validate


def _feature(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "id": "feat-001",
        "name": "Thing",
        "description": "Does a thing.",
        "status": "done",
        "evidence": "pytest: 3 passed",
    }
    base.update(overrides)
    return base


def test_healthy_list_passes() -> None:
    report = validate([_feature(), _feature(id="feat-002", status="planned", evidence="")])
    assert report["is_valid"] is True
    assert report["errors"] == []


def test_done_without_evidence_is_flagged() -> None:
    report = validate([_feature(evidence="")])
    assert report["is_valid"] is False
    assert report["done_without_evidence"] == ["feat-001"]


def test_done_with_whitespace_evidence_is_flagged() -> None:
    report = validate([_feature(evidence="   ")])
    assert report["done_without_evidence"] == ["feat-001"]


def test_done_with_missing_evidence_key_is_flagged() -> None:
    entry = _feature()
    del entry["evidence"]
    assert validate([entry])["done_without_evidence"] == ["feat-001"]


@pytest.mark.parametrize("evidence", [[""], [" "], {"a": ""}, 0, None, True, 5, [True]])
def test_done_with_non_string_evidence_is_flagged(evidence: object) -> None:
    assert validate([_feature(evidence=evidence)])["done_without_evidence"] == ["feat-001"]


def test_non_done_without_evidence_is_allowed() -> None:
    report = validate([_feature(status="active", evidence="")])
    assert report["done_without_evidence"] == []
    assert report["is_valid"] is True


@pytest.mark.parametrize("field", ["id", "name", "description", "status"])
def test_missing_required_field_is_a_schema_error(field: str) -> None:
    entry = _feature()
    del entry[field]
    report = validate([entry])
    assert report["is_valid"] is False
    assert any(field in e for e in report["errors"])


def test_duplicate_ids_are_flagged() -> None:
    report = validate([_feature(), _feature()])
    assert report["is_valid"] is False
    assert any("duplicate" in e.lower() for e in report["errors"])


def test_non_dict_entry_is_a_schema_error() -> None:
    report = validate(["feat-001"])
    assert report["is_valid"] is False


def test_load_accepts_wrapped_object_and_bare_list(tmp_path: Path) -> None:
    wrapped = tmp_path / "wrapped.json"
    wrapped.write_text(json.dumps({"features": [_feature()]}), encoding="utf-8")
    bare = tmp_path / "bare.json"
    bare.write_text(json.dumps([_feature()]), encoding="utf-8")
    assert load_features(wrapped) == load_features(bare)


def test_load_accepts_a_directory_like_the_original(tmp_path: Path) -> None:
    (tmp_path / "feature_list.json").write_text(
        json.dumps({"features": [_feature()]}), encoding="utf-8"
    )
    assert load_features(tmp_path) == [_feature()]


def test_load_rejects_other_shapes(tmp_path: Path) -> None:
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps({"nope": 1}), encoding="utf-8")
    with pytest.raises(ValueError):
        load_features(bad)


def test_real_feature_list_is_valid() -> None:
    root = Path(__file__).resolve().parents[4]
    report = validate(load_features(root / "feature_list.json"))
    assert report["errors"] == []
    assert report["done_without_evidence"] == []
