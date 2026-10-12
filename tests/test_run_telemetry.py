"""Tests for scripts/run_telemetry.py (read-only run telemetry collector)."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import run_telemetry as rt

SESSION = "11111111-aaaa-bbbb-cccc-222222222222"
T0 = "2026-10-12T02:00:00.000Z"


def _ts(minute: int, second: int = 0) -> str:
    return f"2026-10-12T02:{minute:02d}:{second:02d}.000Z"


def _usage(i: int, o: int, cr: int | None = None, cc: int | None = None) -> dict[str, int]:
    u = {"input_tokens": i, "output_tokens": o}
    if cr is not None:
        u["cache_read_input_tokens"] = cr
    if cc is not None:
        u["cache_creation_input_tokens"] = cc
    return u


def _row(
    ts: str,
    mid: str | None,
    usage: dict[str, int] | None,
    *,
    content: list[dict[str, Any]] | None = None,
    model: str = "model-a",
) -> dict[str, Any]:
    msg: dict[str, Any] = {"model": model, "content": content or []}
    if mid is not None:
        msg["id"] = mid
    if usage is not None:
        msg["usage"] = usage
    return {"type": "assistant", "timestamp": ts, "uuid": f"u-{ts}-{mid}", "message": msg}


def _write(path: Path, rows: list[Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for r in rows:
            f.write((r if isinstance(r, str) else json.dumps(r)) + "\n")


def _session(tmp_path: Path, rows: list[Any]) -> Path:
    p = tmp_path / f"{SESSION}.jsonl"
    _write(p, rows)
    return p


def _subagent(
    tmp_path: Path,
    agent_id: str,
    rows: list[Any],
    *,
    tool_use_id: str = "toolu_1",
    agent_type: str = "general-purpose",
    description: str = "review the diff",
) -> None:
    d = tmp_path / SESSION / "subagents"
    _write(d / f"agent-{agent_id}.jsonl", rows)
    meta = {"agentType": agent_type, "description": description, "toolUseId": tool_use_id}
    (d / f"agent-{agent_id}.meta.json").write_text(json.dumps(meta))


def _status(m: dict[str, Any]) -> str:
    return m["status"]


def test_identical_duplicate_rows_count_once(tmp_path):
    rows = [
        _row(_ts(1), "m1", _usage(100, 10, 0, 0)),
        _row(_ts(1, 1), "m1", _usage(100, 10, 0, 0)),
        _row(_ts(2), "m2", _usage(200, 20, 0, 0)),
    ]
    run = rt.collect_run(_session(tmp_path, rows))
    tok = run["parent"]["tokens"]
    assert tok["output_tokens_sum"]["value"] == 30
    assert tok["input_tokens_sum"]["value"] == 300
    assert run["parent"]["usage_rows"] == 3
    assert run["parent"]["distinct_message_ids"] == 2
    assert run["parent"]["conflicts"] == []


def test_conflicting_duplicate_rows_flagged_and_raw_rows_kept(tmp_path):
    rows = [
        _row(_ts(1), "m1", _usage(100, 5, 0, 0)),
        _row(_ts(1, 2), "m1", _usage(100, 40, 0, 0)),
    ]
    run = rt.collect_run(_session(tmp_path, rows))
    assert run["parent"]["tokens"]["output_tokens_sum"]["value"] == 40
    conflict = run["parent"]["conflicts"]
    assert len(conflict) == 1 and conflict[0]["message_id"] == "m1"
    assert [r["output_tokens"] for r in conflict[0]["raw_rows"]] == [5, 40]


def test_absent_cache_field_is_missing_but_present_zero_is_measured(tmp_path):
    absent = rt.collect_run(_session(tmp_path, [_row(_ts(1), "m1", _usage(10, 1))]))
    assert _status(absent["parent"]["tokens"]["cache_read_sum"]) == "missing"
    assert absent["parent"]["tokens"]["cache_read_sum"]["value"] is None

    present = rt.collect_run(_session(tmp_path, [_row(_ts(1), "m1", _usage(10, 1, 0, 0))]))
    cache = present["parent"]["tokens"]["cache_read_sum"]
    assert cache["value"] == 0
    assert cache["status"] == "measured"
    assert cache["source"] == "session usage rows"


def test_rows_without_message_id_are_not_collapsed_and_are_reported(tmp_path):
    rows = [_row(_ts(1), None, _usage(10, 1, 0, 0)), _row(_ts(2), None, _usage(10, 1, 0, 0))]
    run = rt.collect_run(_session(tmp_path, rows))
    assert run["parent"]["tokens"]["output_tokens_sum"]["value"] == 2
    assert run["parent"]["rows_without_message_id"] == 2


def test_subagent_tokens_never_added_to_parent_or_parsed_from_text(tmp_path):
    spawn = {"type": "tool_use", "id": "toolu_1", "name": "Agent", "input": {"description": "x"}}
    note = {
        "type": "user",
        "timestamp": _ts(5),
        "message": {"content": "<subagent_tokens>999999</subagent_tokens>"},
    }
    rows = [_row(_ts(1), "p1", _usage(100, 10, 0, 0), content=[spawn]), note]
    _subagent(tmp_path, "abc", [_row(_ts(2), "s1", _usage(5000, 500, 0, 0))])
    run = rt.collect_run(_session(tmp_path, rows))
    assert run["parent"]["tokens"]["input_tokens_sum"]["value"] == 100
    sub = run["subagents"][0]
    assert sub["tokens"]["input_tokens_sum"]["value"] == 5000
    assert "999999" not in json.dumps(run)


def test_subagent_metadata_attributed(tmp_path):
    spawn = {"type": "tool_use", "id": "toolu_1", "name": "Agent", "input": {}}
    _subagent(
        tmp_path,
        "abc",
        [
            _row(_ts(2), "s1", _usage(10, 1, 0, 0), model="model-b"),
            _row(_ts(4), "s2", _usage(12, 2)),
        ],
    )
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "p1", _usage(1, 1), content=[spawn])]))
    s = run["subagents"][0]
    assert s["agent_id"] == "abc"
    assert s["parent_session_id"] == SESSION[:8]
    assert s["tool_use_id"] == "toolu_1"
    assert s["agent_type"] == "general-purpose"
    assert s["description"] == "review the diff"
    assert s["model"] == {
        "value": ["model-b", "model-a"],
        "source": "assistant message",
        "status": "measured",
    }
    assert s["duration_ms"]["value"] == 120000
    assert _status(s["outcome"]) == "missing"
    assert run["spawn_calls"]["value"] == 1
    assert run["unmatched_spawns"] == []


def test_spawn_without_transcript_is_reported_unmatched(tmp_path):
    spawn = {"type": "tool_use", "id": "toolu_zzz", "name": "Agent", "input": {}}
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "p1", _usage(1, 1), content=[spawn])]))
    assert run["spawn_calls"]["value"] == 1
    assert run["subagent_count"]["value"] == 0
    assert run["unmatched_spawns"] == ["toolu_zzz"]


def test_wall_time_and_agent_time_are_separate_with_overlapping_subagents(tmp_path):
    _subagent(
        tmp_path,
        "a",
        [_row(_ts(1), "s1", _usage(1, 1)), _row(_ts(5), "s2", _usage(1, 1))],
        tool_use_id="t1",
    )
    _subagent(
        tmp_path,
        "b",
        [_row(_ts(2), "s3", _usage(1, 1)), _row(_ts(6), "s4", _usage(1, 1))],
        tool_use_id="t2",
    )
    rows = [_row(_ts(0), "p1", _usage(1, 1)), _row(_ts(10), "p2", _usage(1, 1))]
    run = rt.collect_run(_session(tmp_path, rows))
    assert run["wall_time_ms"]["value"] == 600000
    assert run["agent_time_ms"]["value"] == 480000
    assert run["agent_time_ms"]["note"]


def test_window_excludes_rows_outside_it(tmp_path):
    rows = [
        _row(_ts(1), "m1", _usage(100, 10, 0, 0)),
        _row(_ts(30), "m2", _usage(200, 20, 0, 0)),
        _row(_ts(50), "m3", _usage(400, 40, 0, 0)),
    ]
    run = rt.collect_run(_session(tmp_path, rows), start=_ts(20), end=_ts(40))
    assert run["parent"]["tokens"]["input_tokens_sum"]["value"] == 200


def test_empty_window_has_all_metrics_missing_not_zero(tmp_path):
    run = rt.collect_run(
        _session(tmp_path, [_row(_ts(1), "m1", _usage(1, 1, 0, 0))]), start=_ts(30), end=_ts(40)
    )
    for name in ("input_tokens_sum", "output_tokens_sum", "cache_read_sum", "cache_creation_sum"):
        assert run["parent"]["tokens"][name]["value"] is None
        assert _status(run["parent"]["tokens"][name]) == "missing"
    assert _status(run["wall_time_ms"]) == "missing"


def test_incomplete_session_without_assistant_rows_does_not_crash(tmp_path):
    rows = [{"type": "user", "timestamp": _ts(1), "message": {"content": "hi"}}]
    run = rt.collect_run(_session(tmp_path, rows))
    assert _status(run["parent"]["tokens"]["output_tokens_sum"]) == "missing"
    assert run["parent"]["usage_rows"] == 0


def test_malformed_lines_are_skipped_and_counted(tmp_path):
    rows = ["not json", _row(_ts(1), "m1", _usage(10, 1, 0, 0)), "{broken"]
    run = rt.collect_run(_session(tmp_path, rows))
    assert run["parent"]["tokens"]["input_tokens_sum"]["value"] == 10
    assert run["parent"]["malformed_lines"] == 2


def test_context_size_is_labeled_and_matches_harness_figure_without_cache(tmp_path):
    rows = [
        _row(_ts(1), "m1", _usage(24353, 0, 0, 0)),
        _row(_ts(2), "m2", _usage(45541, 555, 0, 0)),
    ]
    tok = rt.collect_run(_session(tmp_path, rows))["parent"]["tokens"]
    assert tok["last_context_tokens"]["value"] == 45541
    assert tok["reported_context_total"]["value"] == 46096
    assert "not billed" in tok["reported_context_total"]["note"]
    assert tok["input_tokens_sum"]["value"] == 24353 + 45541


def test_structured_event_counts_and_unavailable_metrics(tmp_path):
    rows = [
        _row(_ts(1), "m1", _usage(1, 1, 0, 0)),
        {"type": "system", "subtype": "compact_boundary", "timestamp": _ts(2)},
        {
            "type": "assistant",
            "timestamp": _ts(3),
            "isApiErrorMessage": True,
            "error": "x",
            "message": {},
        },
    ]
    run = rt.collect_run(_session(tmp_path, rows))
    assert run["events"]["context_compactions"] == {
        "value": 1,
        "source": "system compact_boundary records",
        "status": "measured",
    }
    assert run["events"]["api_errors"]["value"] == 1
    assert _status(run["events"]["retries"]) == "missing"
    assert _status(run["events"]["timeouts"]) == "missing"
    assert _status(run["human_corrections"]) == "missing"


def test_cost_usd_is_missing_with_reason(tmp_path):
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "m1", _usage(1, 1, 0, 0))]))
    assert run["cost_usd"]["value"] is None
    assert _status(run["cost_usd"]) == "missing"
    assert "authoritative" in run["cost_usd"]["note"]


def test_run_id_is_deterministic_and_window_sensitive(tmp_path):
    p = _session(tmp_path, [_row(_ts(1), "m1", _usage(1, 1))])
    a = rt.collect_run(p)["run_id"]
    assert a == rt.collect_run(p)["run_id"]
    assert a != rt.collect_run(p, start=_ts(0), end=_ts(5))["run_id"]


def test_gate_report_embedded_when_given_and_missing_otherwise(tmp_path):
    p = _session(tmp_path, [_row(_ts(1), "m1", _usage(1, 1))])
    assert _status(rt.collect_run(p)["gates"]) == "missing"
    report = tmp_path / "report.json"
    report.write_text(
        json.dumps(
            {
                "status": "PASS",
                "total_duration_ms": 5,
                "gates": [{"name": "g", "status": "PASS", "duration_ms": 5}],
                "failed": [],
            }
        )
    )
    gates = rt.collect_run(p, verify_report=report)["gates"]
    assert gates["status"] == "measured" and gates["value"]["status"] == "PASS"


def test_outside_agent_log_counts_attempts_and_flags_legacy_success_only_rows(tmp_path):
    p = _session(tmp_path, [_row(_ts(1), "m1", _usage(1, 1))])
    log = tmp_path / "outside.jsonl"
    log.write_text(
        "\n".join(
            json.dumps(r)
            for r in [
                {"timestamp": _ts(2), "agent": "codex-kiro", "exit_code": 0, "independent": True},
                {
                    "timestamp": _ts(3),
                    "agent": "agy",
                    "attempt": True,
                    "result": "timeout",
                    "duration_ms": 110000,
                },
                {
                    "timestamp": _ts(4),
                    "agent": "agy",
                    "attempt": True,
                    "result": "ok",
                    "duration_ms": 9000,
                },
                {
                    "timestamp": _ts(50),
                    "agent": "agy",
                    "attempt": True,
                    "result": "ok",
                    "duration_ms": 1,
                },
            ]
        )
    )
    out = rt.collect_run(p, start=_ts(0), end=_ts(10), outside_log=log)["outside_agent"]
    assert out["attempts_logged"]["value"] == 2
    assert out["results"] == {"timeout": 1, "ok": 1}
    assert out["legacy_success_only_rows"]["value"] == 1
    assert "failures were not logged" in out["legacy_success_only_rows"]["note"]


def test_cli_writes_one_json_per_run(tmp_path, capsys):
    p = _session(tmp_path, [_row(_ts(1), "m1", _usage(10, 1, 0, 0))])
    out_dir = tmp_path / "runs"
    assert rt.main(["--session", str(p), "--out-dir", str(out_dir)]) == 0
    files = list(out_dir.glob("*.json"))
    assert len(files) == 1
    data = json.loads(files[0].read_text())
    assert data["run_id"] == files[0].stem
    assert str(tmp_path) not in files[0].read_text()


def test_cli_missing_session_exits_2(tmp_path, capsys):
    assert rt.main(["--session", str(tmp_path / "nope.jsonl"), "--out-dir", str(tmp_path)]) == 2
    assert "nope.jsonl" in capsys.readouterr().err


@pytest.mark.parametrize(
    "ts", ["2026-10-12T02:00:00.000Z", "2026-10-12T02:00:00+00:00", "2026-10-12T10:00:00+08:00"]
)
def test_timestamp_parsing_accepts_z_and_offsets(ts):
    assert rt.parse_ts(ts) == rt.parse_ts(T0)


def test_input_sum_is_labeled_not_unique_and_not_billed(tmp_path):
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "m1", _usage(10, 1, 0, 0))]))
    note = run["parent"]["tokens"]["input_tokens_sum"]["note"]
    assert "re-sent" in note and "not billed" in note


def test_all_zero_cache_is_flagged_ambiguous(tmp_path):
    rows = [_row(_ts(i), f"m{i}", _usage(10, 1, 0, 0)) for i in range(1, 4)]
    tok = rt.collect_run(_session(tmp_path, rows))["parent"]["tokens"]
    for name in ("cache_read_sum", "cache_creation_sum"):
        assert tok[name]["value"] == 0
        assert "cannot tell" in tok[name]["note"]


def test_nonzero_cache_has_no_ambiguity_note(tmp_path):
    tok = rt.collect_run(_session(tmp_path, [_row(_ts(1), "m1", _usage(10, 1, 5, 0))]))["parent"][
        "tokens"
    ]
    assert "note" not in tok["cache_read_sum"]


def test_active_turn_time_sums_turn_duration_records_in_window(tmp_path):
    rows = [
        _row(_ts(1), "m1", _usage(1, 1, 0, 0)),
        {"type": "system", "subtype": "turn_duration", "durationMs": 4000, "timestamp": _ts(2)},
        {"type": "system", "subtype": "turn_duration", "durationMs": 6000, "timestamp": _ts(3)},
        {"type": "system", "subtype": "turn_duration", "durationMs": 9000, "timestamp": _ts(40)},
    ]
    p = _session(tmp_path, rows)
    assert rt.collect_run(p, start=_ts(0), end=_ts(10))["active_turn_time_ms"]["value"] == 10000
    assert "idle" in rt.collect_run(p)["wall_time_ms"]["note"]


def test_active_turn_time_missing_without_records(tmp_path):
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "m1", _usage(1, 1, 0, 0))]))
    assert run["active_turn_time_ms"]["value"] is None
    assert run["active_turn_time_ms"]["status"] == "missing"


def test_subagent_without_parent_spawn_is_flagged_not_dropped(tmp_path):
    spawn = {"type": "tool_use", "id": "toolu_1", "name": "Agent", "input": {}}
    _subagent(tmp_path, "abc", [_row(_ts(2), "s1", _usage(10, 1, 0, 0))], tool_use_id="toolu_1")
    _subagent(
        tmp_path, "skl", [_row(_ts(3), "s2", _usage(20, 2, 0, 0))], tool_use_id="toolu_from_skill"
    )
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "p1", _usage(1, 1), content=[spawn])]))
    assert run["subagent_count"]["value"] == 2
    assert run["spawn_calls"]["value"] == 1
    assert run["subagents_without_spawn"] == ["skl"]
    by_id = {s["agent_id"]: s for s in run["subagents"]}
    assert by_id["skl"]["spawned_by_parent_call"] is False
    assert by_id["abc"]["spawned_by_parent_call"] is True


def test_context_total_is_missing_when_output_is_missing(tmp_path):
    rows = [_row(_ts(1), "m1", {"input_tokens": 7})]
    tok = rt.collect_run(_session(tmp_path, rows))["parent"]["tokens"]
    assert tok["output_tokens_sum"]["status"] == "missing"
    assert tok["reported_context_total"]["status"] == "missing"
    assert tok["reported_context_total"]["value"] is None
    assert tok["last_context_tokens"]["value"] == 7


def test_max_context_tokens_reported(tmp_path):
    rows = [
        _row(_ts(1), "m1", _usage(7, 1, 0, 0)),
        _row(_ts(2), "m2", _usage(9, 1, 0, 0)),
        _row(_ts(3), "m3", _usage(8, 1, 0, 0)),
    ]
    tok = rt.collect_run(_session(tmp_path, rows))["parent"]["tokens"]
    assert tok["max_context_tokens"]["value"] == 9
    assert tok["last_context_tokens"]["value"] == 8


def test_subagent_description_is_bounded_and_scrubbed(tmp_path):
    long_desc = "review " + "x" * 300
    _subagent(
        tmp_path, "abc", [_row(_ts(2), "s1", _usage(1, 1))], description=long_desc, tool_use_id="t1"
    )
    _subagent(
        tmp_path,
        "def",
        [_row(_ts(3), "s2", _usage(1, 1))],
        description="fix /Users/alice/secret/file.py now",
        tool_use_id="t2",
    )
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "p1", _usage(1, 1))]))
    descs = {s["agent_id"]: s["description"] for s in run["subagents"]}
    assert len(descs["abc"]) <= 80 and descs["abc"].endswith("…")
    assert "/Users/alice" not in descs["def"]
    assert descs["def"] == "[redacted: contains a path]"


def test_synthetic_rows_do_not_set_context_size(tmp_path):
    rows = [
        _row(_ts(1), "m1", _usage(500, 10, 0, 0)),
        _row(_ts(2), "m2", _usage(0, 0, 0, 0), model="<synthetic>"),
    ]
    p = rt.collect_run(_session(tmp_path, rows))["parent"]
    assert p["tokens"]["last_context_tokens"]["value"] == 500
    assert p["tokens"]["max_context_tokens"]["value"] == 500
    assert p["synthetic_rows_ignored"] == 1
    assert "<synthetic>" not in p["models"]


def test_only_synthetic_rows_means_context_missing(tmp_path):
    rows = [_row(_ts(1), "m1", _usage(0, 0, 0, 0), model="<synthetic>")]
    tok = rt.collect_run(_session(tmp_path, rows))["parent"]["tokens"]
    assert tok["last_context_tokens"]["status"] == "missing"
    assert tok["output_tokens_sum"]["status"] == "missing"


def test_nested_workflow_subagents_are_read(tmp_path):
    d = tmp_path / SESSION / "subagents" / "workflows" / "wf_1"
    _write(
        d / "agent-nested.jsonl",
        [_row(_ts(2), "n1", _usage(40, 4, 0, 0)), _row(_ts(3), "n2", _usage(50, 5, 0, 0))],
    )
    _write(
        tmp_path / SESSION / "subagents" / "agent-top.jsonl",
        [_row(_ts(2), "t1", _usage(10, 1, 0, 0))],
    )
    (tmp_path / SESSION / "subagents" / "agent-top.meta.json").write_text(
        json.dumps({"toolUseId": "t"})
    )
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "p1", _usage(1, 1, 0, 0))]))
    assert run["subagent_count"]["value"] == 2
    assert {s["agent_id"] for s in run["subagents"]} == {"top", "nested"}


def test_invalid_utf8_bytes_are_counted_as_malformed_not_a_crash(tmp_path):
    p = tmp_path / f"{SESSION}.jsonl"
    good = json.dumps(_row(_ts(1), "m1", _usage(5, 1, 0, 0))).encode()
    p.write_bytes(b"\xff\xfe\x00bad\n" + good + b"\n")
    run = rt.collect_run(p)
    assert run["parent"]["malformed_lines"] == 1
    assert run["parent"]["tokens"]["input_tokens_sum"]["value"] == 5


def test_nonhashable_tool_use_id_and_nan_duration_do_not_crash(tmp_path):
    d = tmp_path / SESSION / "subagents"
    _write(d / "agent-x.jsonl", [_row(_ts(2), "s1", _usage(1, 1, 0, 0))])
    (d / "agent-x.meta.json").write_text(json.dumps({"toolUseId": ["a"], "agentType": "t"}))
    rows = [
        _row(_ts(1), "p1", _usage(1, 1, 0, 0)),
        {
            "type": "system",
            "subtype": "turn_duration",
            "durationMs": float("nan"),
            "timestamp": _ts(2),
        },
    ]
    p = _session(tmp_path, [json.dumps(r) if isinstance(r, dict) else r for r in rows])
    run = rt.collect_run(p)
    assert run["subagents"][0]["tool_use_id"] is None
    assert run["active_turn_time_ms"]["status"] == "missing"


def test_agent_type_and_session_id_are_scrubbed(tmp_path):
    secret = tmp_path / "my-secret-client-x.jsonl"
    _write(secret, [_row(_ts(1), "m1", _usage(1, 1, 0, 0))])
    d = tmp_path / "my-secret-client-x" / "subagents"
    _write(d / "agent-a.jsonl", [_row(_ts(2), "s1", _usage(1, 1, 0, 0))])
    (d / "agent-a.meta.json").write_text(
        json.dumps(
            {
                "toolUseId": "t",
                "agentType": "/Users/herohsu/secret",
                "description": "password=hunter2 sk-ant-abc123",
            }
        )
    )
    run = rt.collect_run(secret)
    text = json.dumps(run)
    assert "my-secret-client-x" not in text
    assert "/Users/herohsu" not in text
    assert "hunter2" not in text and "sk-ant-abc123" not in text
    assert len(run["session_id"]) <= 12


def test_window_cutting_duplicate_rows_is_flagged(tmp_path):
    rows = [
        _row(_ts(0), "m1", _usage(10, 1, 0, 0)),
        _row(_ts(10), "m1", _usage(10, 50, 0, 0)),
    ]
    run = rt.collect_run(_session(tmp_path, rows), start=_ts(0), end=_ts(5))
    assert run["parent"]["partial_message_ids"] == ["m1"]


def test_adjacent_windows_do_not_both_count_a_boundary_row(tmp_path):
    rows = [_row(_ts(5), "m1", _usage(10, 1, 0, 0))]
    p = _session(tmp_path, rows)
    a = rt.collect_run(p, start=_ts(0), end=_ts(5))["parent"]["usage_rows"]
    b = rt.collect_run(p, start=_ts(5), end=_ts(10))["parent"]["usage_rows"]
    assert a + b == 1


def test_boolean_token_values_are_not_counted(tmp_path):
    rows = [_row(_ts(1), "m1", {"input_tokens": True, "output_tokens": 3})]
    tok = rt.collect_run(_session(tmp_path, rows))["parent"]["tokens"]
    assert tok["input_tokens_sum"]["status"] == "missing"
    assert tok["output_tokens_sum"]["value"] == 3


def test_conflict_in_cache_fields_only_is_flagged(tmp_path):
    rows = [
        _row(_ts(1), "m1", _usage(10, 5, 0, 0)),
        _row(_ts(2), "m1", _usage(10, 5, 7, 0)),
    ]
    assert len(rt.collect_run(_session(tmp_path, rows))["parent"]["conflicts"]) == 1


def test_subagent_outside_window_is_excluded(tmp_path):
    _subagent(tmp_path, "early", [_row(_ts(1), "s1", _usage(10, 1, 0, 0))])
    _subagent(tmp_path, "late", [_row(_ts(30), "s2", _usage(20, 2, 0, 0))], tool_use_id="t2")
    run = rt.collect_run(
        _session(tmp_path, [_row(_ts(0), "p", _usage(1, 1, 0, 0))]), start=_ts(20), end=_ts(40)
    )
    assert [s["agent_id"] for s in run["subagents"]] == ["late"]


def test_subagent_partial_ids_are_reported(tmp_path):
    _subagent(
        tmp_path,
        "abc",
        [_row(_ts(1), "s", _usage(10, 1, 0, 0)), _row(_ts(5), "s", _usage(10, 1, 0, 0))],
    )
    run = rt.collect_run(
        _session(tmp_path, [_row(_ts(0), "p", _usage(1, 1, 0, 0))]), start=_ts(0), end=_ts(2)
    )
    assert run["subagents"][0]["partial_message_ids"] == ["s"]


@pytest.mark.parametrize(
    "text",
    [
        "Authorization: Bearer abcdef1234567890",
        "api_key=abcd1234",
        "API-KEY: abc123",
        "pwd=hunter2",
        "passwd: hunter2",
        "secrets=abc",
        "gh" + "p_abcdefghijklmnop1234",
        "AK" + "IA" + "ABCDEFGHIJKLMNOP",
        "xo" + "xb-1234-abcdef",
        "ey" + "JhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc",
        "C:\\Users\\x\\proj",
        "\\\\server\\share\\file",
        "/tmp/build/out",
        "/etc/passwd",
        "/opt/app/run",
        "/private/var/x",
        "\u2215Users\u2215bob",
    ],
    ids=lambda v: "case",
)
def test_description_scrub_blocks_secret_and_path_shapes(text):
    out = rt._scrub(text)
    assert out == "[redacted]" or out.startswith("[redacted")
    assert "hunter2" not in out and "abcd1234" not in out and "ghp_" not in out


def test_description_scrub_keeps_plain_labels():
    assert rt._scrub("Fresh review of uncommitted changes") == "Fresh review of uncommitted changes"
    assert rt._scrub("Verify ./init.sh on a clean copy") == "Verify ./init.sh on a clean copy"
    assert rt._scrub("/code-review") == "/code-review"


def test_agent_and_tool_use_ids_must_be_opaque_tokens(tmp_path):
    d = tmp_path / SESSION / "subagents"
    _write(d / "agent-ghp_secrettoken123456.jsonl", [_row(_ts(2), "s1", _usage(1, 1, 0, 0))])
    (d / "agent-ghp_secrettoken123456.meta.json").write_text(
        json.dumps({"toolUseId": "password=hunter2", "agentType": "t"})
    )
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "p", _usage(1, 1, 0, 0))]))
    text = json.dumps(run)
    assert "ghp_secrettoken123456" not in text
    assert "hunter2" not in text
    sub = run["subagents"][0]
    assert sub["agent_id"].startswith("agent-")
    assert sub["tool_use_id"] is None


def test_duplicate_agent_file_names_get_distinct_ids(tmp_path):
    base = tmp_path / SESSION / "subagents"
    _write(base / "workflows" / "wf_a" / "agent-x1.jsonl", [_row(_ts(2), "a", _usage(1, 1, 0, 0))])
    _write(base / "workflows" / "wf_b" / "agent-x1.jsonl", [_row(_ts(3), "b", _usage(1, 1, 0, 0))])
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "p", _usage(1, 1, 0, 0))]))
    ids = [s["agent_id"] for s in run["subagents"]]
    assert len(ids) == len(set(ids)) == 2


def test_overflowing_durations_and_string_token_values_do_not_crash(tmp_path):
    rows = [
        {"type": "system", "subtype": "turn_duration", "durationMs": 1e308, "timestamp": _ts(1)},
        {"type": "system", "subtype": "turn_duration", "durationMs": 1e308, "timestamp": _ts(2)},
        _row(_ts(3), "m", {"input_tokens": 1, "output_tokens": "5"}),
        _row(_ts(4), "m", {"input_tokens": 1, "output_tokens": 3}),
    ]
    run = rt.collect_run(_session(tmp_path, rows))
    assert run["active_turn_time_ms"]["status"] == "missing"
    assert len(run["parent"]["conflicts"]) == 1


def test_rows_without_timestamp_are_counted_when_windowed(tmp_path):
    row = _row(_ts(1), "m", _usage(5, 1, 0, 0))
    del row["timestamp"]
    run = rt.collect_run(_session(tmp_path, [row]), start=_ts(0), end=_ts(5))
    assert run["parent"]["rows_without_timestamp_excluded"] == 1
    assert run["parent"]["usage_rows"] == 0


def test_boolean_duration_is_not_a_duration(tmp_path):
    rows = [{"type": "system", "subtype": "turn_duration", "durationMs": True, "timestamp": _ts(1)}]
    assert rt.collect_run(_session(tmp_path, rows))["active_turn_time_ms"]["status"] == "missing"


def test_deeply_nested_line_is_malformed_not_a_crash(tmp_path):
    p = _session(tmp_path, [_row(_ts(1), "m", _usage(1, 1)), "[" * 200000])
    run = rt.collect_run(p)
    assert run["parent"]["malformed_lines"] == 1
    assert run["parent"]["tokens"]["output_tokens_sum"]["value"] == 1


def test_huge_integer_duration_does_not_crash(tmp_path):
    rows = [
        _row(_ts(1), "m", _usage(1, 1)),
        '{"type":"system","subtype":"turn_duration","durationMs":'
        + "9" * 400
        + ',"timestamp":"'
        + _ts(2)
        + '"}',
    ]
    run = rt.collect_run(_session(tmp_path, rows))
    assert _status(run["active_turn_time_ms"]) == "missing"


def test_unreadable_subagent_path_does_not_crash(tmp_path):
    (tmp_path / SESSION / "subagents" / "agent-dir.jsonl").mkdir(parents=True)
    run = rt.collect_run(_session(tmp_path, [_row(_ts(1), "m", _usage(1, 1))]))
    assert run["subagent_count"]["value"] == 0


@pytest.mark.parametrize("payload", ["[1]", '"x"', "null", "5"])
def test_gate_report_that_is_not_an_object_is_missing(tmp_path, payload):
    report = tmp_path / "r.json"
    report.write_text(payload)
    run = rt.collect_run(
        _session(tmp_path, [_row(_ts(1), "m", _usage(1, 1))]), verify_report=report
    )
    assert _status(run["gates"]) == "missing"


def test_gate_report_values_are_scrubbed_and_bounded(tmp_path):
    report = tmp_path / "r.json"
    report.write_text(
        json.dumps(
            {
                "status": "FAIL",
                "total_duration_ms": 10,
                "gates": [
                    {
                        "name": "/Users/bob/secret/x",
                        "status": "FAIL",
                        "duration_ms": 3,
                        "extra": "/Users/bob/p",
                    }
                ],
                "failed": ["/Users/bob/secret/x"],
            }
        )
    )
    run = rt.collect_run(
        _session(tmp_path, [_row(_ts(1), "m", _usage(1, 1))]), verify_report=report
    )
    text = json.dumps(run["gates"])
    assert "/Users/bob" not in text
    assert run["gates"]["value"]["gates"][0]["status"] == "FAIL"


def test_free_text_fields_never_carry_paths(tmp_path):
    bad = "/Users/bob/secret/key"
    rows = [
        _row(_ts(1), "m", _usage(1, 1), model=bad),
        _row(
            _ts(2),
            "n",
            _usage(1, 1),
            content=[{"type": "tool_use", "name": "Agent", "id": bad}],
        ),
    ]
    log = tmp_path / "log.jsonl"
    _write(log, [{"attempt": True, "result": "failed at /Users/bob/p", "timestamp": _ts(1)}])
    run = rt.collect_run(_session(tmp_path, rows), outside_log=log)
    assert "/Users/bob" not in json.dumps(run)


@pytest.mark.parametrize(
    "text",
    [
        "".join(["sk_live", "_", "abcdefghijklmnop"]),
        "".join(["AIza", "SyA1234567890abcdefghij"]),
        "".join(["glpat", "-", "abcdefghij1234567890"]),
        "".join(["npm", "_", "abcdefghijklmnop1234"]),
        "".join(["hf", "_", "abcdefghijklmnopqrst"]),
        "Bearer " + "abcdef123456",
        "password " + "hunter2secret",
        "fix ../../etc/passwd",
        "review src/secrets/prod.py",
        "see ~bob/x",
    ],
    ids=lambda v: "case",
)
def test_scrub_covers_more_credential_and_path_shapes(text):
    assert rt._scrub(text).startswith("[redacted")


def test_scrub_keeps_ordinary_labels_with_slashes_or_secret_words():
    assert rt._scrub("Review token budget handling") == "Review token budget handling"
    assert rt._scrub("check and/or input") == "check and/or input"
