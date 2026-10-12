"""Tests for scripts/run_report.py."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import run_report as rr


def _m(value: Any, status: str = "measured") -> dict[str, Any]:
    return {"value": value, "source": "t", "status": status}


def _run(run_id: str, out: int | None, **over: Any) -> dict[str, Any]:
    tokens = {
        "output_tokens_sum": _m(out) if out is not None else _m(None, "missing"),
        "last_context_tokens": _m(1000),
    }
    base: dict[str, Any] = {
        "run_id": run_id,
        "parent": {"tokens": tokens, "conflicts": []},
        "wall_time_ms": _m(90000),
        "active_turn_time_ms": _m(None, "missing"),
        "subagent_count": _m(0),
        "subagents": [],
        "subagents_without_spawn": [],
        "gates": _m(None, "missing"),
    }
    base.update(over)
    return base


def test_missing_metric_prints_na_never_zero():
    r = rr.row(_run("a", None))
    assert r["out_tok"] == "n/a"
    assert r["turns"] == "n/a"
    assert r["gates"] == "n/a"


def test_measured_zero_prints_zero():
    assert rr.row(_run("a", 0))["out_tok"] == "0"


def test_subagent_output_total_only_when_every_subagent_is_known():
    known = {"tokens": {"output_tokens_sum": _m(10)}}
    unknown = {"tokens": {"output_tokens_sum": _m(None, "missing")}}
    all_known = rr.row(_run("a", 1, subagents=[known, known], subagent_count=_m(2)))
    some_unknown = rr.row(_run("a", 1, subagents=[known, unknown], subagent_count=_m(2)))
    assert all_known["sub_out_tok"] == "20"
    assert some_unknown["sub_out_tok"] == "n/a"


def test_unattributed_and_conflicts_are_counted():
    run = _run("a", 1, subagents_without_spawn=["x", "y"])
    run["parent"]["conflicts"] = [{"message_id": "m"}]
    r = rr.row(run)
    assert r["unattributed"] == "2" and r["conflicts"] == "1"


def test_gates_status_shown_when_present():
    assert rr.row(_run("a", 1, gates=_m({"status": "PASS"})))["gates"] == "PASS"


def test_duration_formatting():
    assert rr._fmt_ms(45000) == "45s"
    assert rr._fmt_ms(90000) == "1.5m"
    assert rr._fmt_ms(7200000) == "2.0h"
    assert rr._fmt_ms(None) == "n/a"


def test_render_has_header_rows_and_legend(tmp_path):
    out = rr.render([_run("run-1", 5), _run("run-2", None)])
    lines = out.splitlines()
    assert lines[0].split()[0] == "run" and "gates" in lines[0]
    assert "run-1" in out and "run-2" in out
    assert "n/a = missing, not zero" in out


def test_load_runs_skips_unreadable_and_non_run_files(tmp_path):
    (tmp_path / "ok.json").write_text(json.dumps(_run("ok", 1)))
    (tmp_path / "bad.json").write_text("{nope")
    (tmp_path / "other.json").write_text(json.dumps({"hello": 1}))
    assert [r["run_id"] for r in rr.load_runs(tmp_path)] == ["ok"]


def test_cli_missing_dir_and_empty_dir_exit_2(tmp_path, capsys):
    assert rr.main(["--runs-dir", str(tmp_path / "nope")]) == 2
    (tmp_path / "empty").mkdir()
    assert rr.main(["--runs-dir", str(tmp_path / "empty")]) == 2
    assert "no run records" in capsys.readouterr().err


def test_cli_table_and_json(tmp_path, capsys):
    (tmp_path / "a.json").write_text(json.dumps(_run("a", 7)))
    assert rr.main(["--runs-dir", str(tmp_path)]) == 0
    assert "a" in capsys.readouterr().out
    assert rr.main(["--runs-dir", str(tmp_path), "--json"]) == 0
    assert json.loads(capsys.readouterr().out)[0]["out_tok"] == "7"


def test_malformed_record_shapes_degrade_to_na_without_crashing():
    bad = [
        _run("a", 1, parent=[]),
        _run("b", 1, subagents=[1]),
        _run("c", 1, subagents=None),
        _run("d", 1, wall_time_ms=_m("abc")),
        _run("e", 1, gates=_m([1])),
        _run("f", 1, subagents_without_spawn=None),
        _run("g", 1, subagent_count=_m("x")),
    ]
    for r in bad:
        out = rr.row(r)
        assert out["run"] == r["run_id"]
    assert rr.row(bad[3])["wall"] == "n/a"
    assert rr.row(bad[4])["gates"] == "n/a"
    assert "n/a" in rr.render(bad)


def test_deeply_nested_record_file_is_skipped_not_a_crash(tmp_path):
    (tmp_path / "bad.json").write_text("[" * 200000 + "]" * 200000)
    (tmp_path / "ok.json").write_text(json.dumps(_run("ok", 5)))
    assert [r["run_id"] for r in rr.load_runs(tmp_path)] == ["ok"]
