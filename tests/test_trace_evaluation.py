"""Tests for scripts/trace_evaluation.py helpers."""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import trace_evaluation as te


def _bloated_repo(tmp_path: Path) -> Path:
    (tmp_path / "feature_list.json").write_text("\n" * (te.THRESHOLD_FEATURE_LIST_LINES + 5))
    (tmp_path / "PROGRESS.md").write_text("# progress\n")
    return tmp_path


def test_check_thresholds_flags_bloat_without_detecting_agents(tmp_path, monkeypatch):
    def boom(*_a, **_k):
        raise AssertionError("threshold check must not run agent or outside-run detection")

    monkeypatch.setattr(te, "auto_detect_outside_runs", boom)
    monkeypatch.setattr(te, "get_process_ancestors", boom)

    warnings = te.check_thresholds(_bloated_repo(tmp_path))

    assert len(warnings) == 1
    assert "feature_list.json exceeds" in warnings[0]


def test_check_thresholds_clean_repo_has_no_warnings(tmp_path):
    (tmp_path / "feature_list.json").write_text('{"features": []}\n')
    (tmp_path / "PROGRESS.md").write_text("# progress\n")

    assert te.check_thresholds(tmp_path) == []


def test_snapshot_warnings_match_check_thresholds(tmp_path):
    repo = _bloated_repo(tmp_path)

    snapshot = te.collect_snapshot(
        repo, explicit_agent="claude", duration_ms=1, outside_subagents="0"
    )

    assert snapshot["thresholds"]["warnings"] == te.check_thresholds(repo)
    assert snapshot["thresholds"]["status"] == "WARN"


def test_load_records_skips_blank_and_malformed_lines(tmp_path):
    trace = tmp_path / "trace.jsonl"
    trace.write_text('{"commit": "a"}\n\nnot json\n{"commit": "b"}\n')

    assert [r["commit"] for r in te.load_records(trace)] == ["a", "b"]


def test_load_records_missing_file_is_empty(tmp_path):
    assert te.load_records(tmp_path / "absent.jsonl") == []


def test_trace_row_defaults_for_sparse_record():
    row = te.trace_row({"commit": "abc1234", "timestamp": "2026-10-12T08:07:00+00:00"})

    assert row["commit"] == "abc1234"
    assert row["ts"] == "2026-10-12 08:07:00"
    assert row["status"] == "OK"
    assert row["tokens"] == "~0 tok"
    assert row["done_active"] == "0 (0 act)"


def test_trend_and_dashboard_render_same_row_values(tmp_path):
    trace = tmp_path / "trace.jsonl"
    rec = {
        "commit": "abc1234",
        "timestamp": "2026-10-12T08:07:00+00:00",
        "agent": "claude",
        "duration_str": "5m",
        "state_layer": {
            "total_state_tokens_est": 1234,
            "completed_features": 3,
            "active_features": 1,
        },
        "thresholds": {"status": "WARN", "warnings": ["x"]},
    }
    trace.write_text(json.dumps(rec) + "\n")

    md = te.render_markdown_dashboard(trace)

    row = te.trace_row(rec)
    assert row["tokens"] == "~1,234 tok"
    assert row["done_active"] == "3 (1 act)"
    assert row["tokens"] in md
    assert row["done_active"] in md
    assert "**WARN**" in md


def test_trend_table_prints_row_values(tmp_path, capsys):
    trace = tmp_path / "trace.jsonl"
    rec = {
        "commit": "abc1234",
        "timestamp": "2026-10-12T08:07:00+00:00",
        "agent": "claude",
        "duration_str": "5m",
        "state_layer": {
            "total_state_tokens_est": 1234,
            "completed_features": 3,
            "active_features": 1,
        },
        "thresholds": {"status": "WARN", "warnings": ["x"]},
    }
    trace.write_text(json.dumps(rec) + "\n")

    te.render_trend_table(trace)

    out = capsys.readouterr().out
    assert "abc1234" in out
    assert "~1,234 tok" in out
    assert "3 (1 act)" in out
