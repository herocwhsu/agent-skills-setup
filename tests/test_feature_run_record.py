"""Tests for scripts/feature_run_record.py (completion windows, summary backfill, archiving)."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import feature_run_record as fr

SESSION = "0d3a322a-28ca-4d20-a88e-0ae36dde420d"


def _git(repo: Path, *args: str, when: str | None = None) -> str:
    env = {
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@example.invalid",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@example.invalid",
        "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
        "HOME": str(repo),
    }
    if when:
        env["GIT_AUTHOR_DATE"] = when
        env["GIT_COMMITTER_DATE"] = when
    return subprocess.run(
        ["git", *args], cwd=repo, env=env, capture_output=True, text=True, check=True
    ).stdout


def _feature(fid: str, status: str, **extra: Any) -> dict[str, Any]:
    return {
        "id": fid,
        "name": f"name {fid}",
        "status": status,
        "evidence": "e" * 40,
        "verification": "true",
        **extra,
    }


def _write_features(
    repo: Path, features: list[dict[str, Any]], refs: list[str] | None = None
) -> None:
    (repo / "feature_list.json").write_text(
        json.dumps({"archive_references": refs or [], "features": features}, indent=2) + "\n"
    )


def _same_instant(a: str | None, b: str) -> bool:
    return a is not None and fr.run_telemetry.parse_ts(a) == fr.run_telemetry.parse_ts(b)


def _commit(repo: Path, when: str, msg: str = "m") -> None:
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", msg, when=when)


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    r = tmp_path / "repo"
    r.mkdir()
    _git(r, "init", "-q")
    return r


def _usage_row(ts: str, mid: str, out: int) -> dict[str, Any]:
    return {
        "type": "assistant",
        "timestamp": ts,
        "message": {"id": mid, "model": "m", "usage": {"input_tokens": 1, "output_tokens": out}},
    }


def _projects(tmp_path: Path, rows: list[dict[str, Any]]) -> Path:
    p = tmp_path / "projects" / "proj"
    p.mkdir(parents=True)
    (p / f"{SESSION}.jsonl").write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    return tmp_path / "projects"


def test_completion_time_is_the_first_commit_where_the_feature_is_completed(repo):
    _write_features(repo, [_feature("feat-001", "in_progress")])
    _commit(repo, "2026-10-01T10:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed")])
    _commit(repo, "2026-10-01T12:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed", note="edited later")])
    _commit(repo, "2026-10-02T09:00:00+00:00")
    assert _same_instant(fr.completion_time(repo, "feat-001"), "2026-10-01T12:00:00+00:00")


def test_completion_time_missing_when_never_completed_or_unknown(repo):
    _write_features(repo, [_feature("feat-001", "in_progress")])
    _commit(repo, "2026-10-01T10:00:00+00:00")
    assert fr.completion_time(repo, "feat-001") is None
    assert fr.completion_time(repo, "feat-999") is None


def test_completion_time_when_feature_list_has_no_history(repo):
    assert fr.completion_time(repo, "feat-001") is None


def test_completion_time_survives_a_malformed_historic_version(repo):
    (repo / "feature_list.json").write_text("{not json")
    _commit(repo, "2026-10-01T09:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed")])
    _commit(repo, "2026-10-01T10:00:00+00:00")
    assert _same_instant(fr.completion_time(repo, "feat-001"), "2026-10-01T10:00:00+00:00")


def test_features_completed_in_the_same_commit_share_one_window(repo):
    _write_features(
        repo, [_feature("feat-001", "in_progress"), _feature("feat-002", "in_progress")]
    )
    _commit(repo, "2026-10-01T10:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed"), _feature("feat-002", "completed")])
    _commit(repo, "2026-10-01T12:00:00+00:00")
    groups = fr.windows_by_commit(repo, ["feat-001", "feat-002"])
    assert len(groups) == 1
    ((when, ids),) = groups.items()
    assert _same_instant(when, "2026-10-01T12:00:00+00:00") and ids == ["feat-001", "feat-002"]


def test_summary_has_the_same_fields_as_the_existing_hand_written_ones():
    rec = {
        "run_id": "abc",
        "parent": {"tokens": {"output_tokens_sum": {"value": 5, "status": "measured"}}},
        "subagents": [{"tokens": {"output_tokens_sum": {"value": 3, "status": "measured"}}}],
        "subagent_count": {"value": 1, "status": "measured"},
        "wall_time_ms": {"value": 9, "status": "measured"},
        "active_turn_time_ms": {"value": None, "status": "missing"},
    }
    s = fr.summary_from_record(rec)
    assert s == {
        "run_id": "abc",
        "output_tokens": 5,
        "wall_time_ms": 9,
        "active_turn_time_ms": None,
        "subagents": 1,
        "subagent_output_tokens": 3,
    }


def test_summary_marks_unknown_subagent_tokens_as_none_not_zero():
    rec = {
        "run_id": "abc",
        "parent": {"tokens": {}},
        "subagents": [{"tokens": {"output_tokens_sum": {"value": None, "status": "missing"}}}],
    }
    s = fr.summary_from_record(rec)
    assert (
        s["subagent_output_tokens"] is None
        and s["output_tokens"] is None
        and s["subagents"] is None
    )


def test_backfill_sets_the_summary_once_and_never_overwrites(repo):
    data = {"archive_references": [], "features": [_feature("feat-001", "completed")]}
    s1 = {"run_id": "r1", "output_tokens": 1}
    assert fr.apply_summary(data, "feat-001", s1) is True
    assert data["features"][0]["execution_summary"] == s1
    assert fr.apply_summary(data, "feat-001", {"run_id": "r2"}) is False
    assert data["features"][0]["execution_summary"] == s1
    assert fr.apply_summary(data, "feat-404", s1) is False


def test_archive_moves_oldest_completed_features_until_under_budget(repo):
    feats = [_feature(f"feat-{i:03d}", "completed", description="d" * 400) for i in range(1, 9)]
    feats.append(_feature("feat-100", "in_progress"))
    _write_features(repo, feats)
    (repo / "PROGRESS.md").write_text("# p\n")
    moved = fr.archive_to_budget(repo, token_budget=500)
    data = json.loads((repo / "feature_list.json").read_text())
    ids = [f["id"] for f in data["features"]]
    assert "feat-100" in ids and "feat-001" not in ids
    assert moved and moved == [f"feat-{i:03d}" for i in range(1, len(moved) + 1)]
    ref = data["archive_references"][-1]
    archived = json.loads((repo / ref).read_text())["features"]
    assert [f["id"] for f in archived] == moved
    assert fr.state_tokens(repo) <= 500 or len(ids) == 1


def test_archive_never_moves_active_or_unevidenced_features(repo):
    feats = [
        _feature("feat-001", "in_progress", description="d" * 2000),
        _feature("feat-002", "completed", evidence="", description="d" * 2000),
        _feature("feat-003", "completed", description="d" * 2000),
    ]
    _write_features(repo, feats)
    (repo / "PROGRESS.md").write_text("# p\n")
    moved = fr.archive_to_budget(repo, token_budget=10)
    ids = [f["id"] for f in json.loads((repo / "feature_list.json").read_text())["features"]]
    assert moved == ["feat-003"] and "feat-001" in ids and "feat-002" in ids


def test_archive_is_a_noop_under_budget_and_keeps_existing_references(repo):
    _write_features(
        repo, [_feature("feat-001", "completed")], refs=["docs/archive/features/old.json"]
    )
    (repo / "PROGRESS.md").write_text("# p\n")
    before = (repo / "feature_list.json").read_text()
    assert fr.archive_to_budget(repo, token_budget=100000) == []
    assert (repo / "feature_list.json").read_text() == before


def test_archive_keeps_all_data_and_the_state_layer_check_still_passes(repo):
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    import state_layer_check

    feats = [_feature(f"feat-{i:03d}", "completed", description="d" * 400) for i in range(1, 7)]
    _write_features(repo, feats)
    (repo / "PROGRESS.md").write_text("# p\n")
    fr.archive_to_budget(repo, token_budget=400)
    state_layer_check.check(repo / "feature_list.json", [])
    data = json.loads((repo / "feature_list.json").read_text())
    kept = {f["id"] for f in data["features"]}
    archived = {
        f["id"]
        for ref in data["archive_references"]
        for f in json.loads((repo / ref).read_text())["features"]
    }
    assert kept | archived == {f["id"] for f in feats} and not (kept & archived)


def test_record_feature_end_to_end_writes_run_record_and_summary(repo, tmp_path):
    _write_features(repo, [_feature("feat-001", "in_progress")])
    _commit(repo, "2026-10-01T10:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed")])
    _commit(repo, "2026-10-01T12:00:00+00:00")
    projects = _projects(
        tmp_path,
        [
            _usage_row("2026-10-01T10:30:00Z", "m1", 40),
            _usage_row("2026-10-01T11:30:00Z", "m2", 60),
            _usage_row("2026-10-01T13:00:00Z", "m3", 900),
        ],
    )
    out = fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)
    assert out["status"] == "recorded"
    data = json.loads((repo / "feature_list.json").read_text())
    s = data["features"][0]["execution_summary"]
    assert s["output_tokens"] == 100
    assert (repo / "docs" / "telemetry" / "runs" / f"{s['run_id']}.json").is_file()


def test_record_feature_starts_after_the_previous_record_of_the_same_session(repo, tmp_path):
    for fid, when in (
        ("feat-001", "2026-10-01T12:00:00+00:00"),
        ("feat-002", "2026-10-01T14:00:00+00:00"),
    ):
        feats = [_feature(f, "completed") for f in ("feat-001", "feat-002") if f <= fid]
        _write_features(repo, feats)
        _commit(repo, when)
    projects = _projects(
        tmp_path,
        [
            _usage_row("2026-10-01T11:00:00Z", "m1", 10),
            _usage_row("2026-10-01T13:00:00Z", "m2", 20),
        ],
    )
    a = fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)
    b = fr.record_feature(repo, "feat-002", SESSION, projects, outside_log=None)
    data = {f["id"]: f for f in json.loads((repo / "feature_list.json").read_text())["features"]}
    assert (a["status"], b["status"]) == ("recorded", "recorded")
    assert data["feat-001"]["execution_summary"]["output_tokens"] == 10
    assert data["feat-002"]["execution_summary"]["output_tokens"] == 20


def test_record_feature_skips_what_it_cannot_measure_and_says_why(repo, tmp_path):
    _write_features(repo, [_feature("feat-001", "in_progress")])
    _commit(repo, "2026-10-01T10:00:00+00:00")
    projects = _projects(tmp_path, [_usage_row("2026-10-01T10:30:00Z", "m1", 10)])
    assert (
        fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)["status"]
        == "not completed"
    )
    assert (
        fr.record_feature(repo, "feat-404", SESSION, projects, outside_log=None)["status"]
        == "not completed"
    )
    _write_features(repo, [_feature("feat-001", "completed")])
    _commit(repo, "2026-10-02T10:00:00+00:00")
    assert (
        fr.record_feature(
            repo, "feat-001", "11111111-2222-3333-4444-555555555555", projects, outside_log=None
        )["status"]
        == "no transcript"
    )
    first = fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)
    assert first["status"] == "recorded"
    assert (
        fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)["status"]
        == "already recorded"
    )


def test_record_feature_with_no_activity_in_the_window_writes_nothing(repo, tmp_path):
    _write_features(repo, [_feature("feat-001", "completed")])
    _commit(repo, "2026-10-01T12:00:00+00:00")
    projects = _projects(tmp_path, [_usage_row("2026-10-05T10:00:00Z", "m1", 10)])
    out = fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)
    assert out["status"] == "no activity"
    assert (
        "execution_summary"
        not in json.loads((repo / "feature_list.json").read_text())["features"][0]
    )


def test_a_completion_that_is_not_committed_is_reported_as_such(repo, tmp_path, capsys):
    _write_features(repo, [_feature("feat-001", "in_progress")])
    _commit(repo, "2026-10-01T10:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed")])
    projects = _projects(tmp_path, [_usage_row("2026-10-01T10:30:00Z", "m1", 10)])
    out = fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)
    assert out["status"] == "completion not committed"
    feat = json.loads((repo / "feature_list.json").read_text())["features"][0]
    assert "execution_summary" not in feat
    # a feature that is not completed keeps the old wording
    _write_features(repo, [_feature("feat-001", "in_progress")])
    out = fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)
    assert out["status"] == "not completed"


def test_main_prints_the_uncommitted_completion_status(repo, tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("CLAUDE_CODE_SESSION_ID", SESSION)
    _write_features(repo, [_feature("feat-001", "in_progress")])
    _commit(repo, "2026-10-01T10:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed")])
    projects = _projects(tmp_path, [_usage_row("2026-10-01T10:30:00Z", "m1", 10)])
    assert fr.main(["--repo", str(repo), "--projects-dir", str(projects), "--pending"]) == 0
    assert "feat-001: completion not committed" in capsys.readouterr().out


def _complete_with_activity(repo: Path, tmp_path: Path) -> Path:
    _write_features(repo, [_feature("feat-001", "in_progress")])
    _commit(repo, "2026-10-01T10:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed")])
    _commit(repo, "2026-10-01T12:00:00+00:00")
    return _projects(tmp_path, [_usage_row("2026-10-01T10:30:00Z", "m1", 10)])


def _run_record(repo: Path) -> dict[str, Any]:
    run_id = json.loads((repo / "feature_list.json").read_text())["features"][0][
        "execution_summary"
    ]["run_id"]
    return json.loads((repo / "docs" / "telemetry" / "runs" / f"{run_id}.json").read_text())


def test_record_feature_carries_the_gate_runs_of_its_window(repo, tmp_path):
    projects = _complete_with_activity(repo, tmp_path)
    log = tmp_path / "harness-verify-runs.jsonl"
    log.write_text(
        json.dumps({"timestamp": "2026-10-01T11:00:00Z", "status": "PASS", "failed": []})
        + "\n"
        + json.dumps({"timestamp": "2026-10-02T11:00:00Z", "status": "FAIL", "failed": ["tests"]})
        + "\n"
    )
    out = fr.record_feature(
        repo, "feat-001", SESSION, projects, outside_log=None, gate_runs_log=log
    )
    assert out["status"] == "recorded"
    g = _run_record(repo)["gate_runs"]
    assert g["status"] == "measured" and g["value"]["count"] == 1 and g["value"]["passed"] == 1


def test_main_finds_the_gate_runs_log_next_to_the_gate_report(repo, tmp_path, monkeypatch):
    monkeypatch.setenv("CLAUDE_CODE_SESSION_ID", SESSION)
    projects = _complete_with_activity(repo, tmp_path)
    state = tmp_path / "state"
    state.mkdir()
    (state / "harness-verify-runs.jsonl").write_text(
        json.dumps({"timestamp": "2026-10-01T11:00:00Z", "status": "PASS", "failed": []}) + "\n"
    )
    code = fr.main(
        [
            "--repo",
            str(repo),
            "--projects-dir",
            str(projects),
            "--pending",
            "--gate-report",
            str(state / "harness-verify-last.json"),
            "--outside-log",
            str(tmp_path / "none.jsonl"),
        ]
    )
    assert code == 0
    assert _run_record(repo)["gate_runs"]["value"]["count"] == 1


def test_main_follows_harness_verify_last_report_and_an_empty_value_means_no_log(
    repo, tmp_path, monkeypatch
):
    monkeypatch.setenv("CLAUDE_CODE_SESSION_ID", SESSION)
    projects = _complete_with_activity(repo, tmp_path)
    state = tmp_path / "custom"
    state.mkdir()
    (state / "harness-verify-runs.jsonl").write_text(
        json.dumps({"timestamp": "2026-10-01T11:00:00Z", "status": "PASS", "failed": []}) + "\n"
    )
    monkeypatch.setenv("HARNESS_VERIFY_LAST_REPORT", str(state / "last.json"))
    args = ["--repo", str(repo), "--projects-dir", str(projects), "--pending"]
    args += ["--outside-log", str(tmp_path / "none.jsonl")]
    assert fr.main(args) == 0
    assert _run_record(repo)["gate_runs"]["value"]["count"] == 1

    _write_features(repo, [_feature("feat-001", "in_progress")])
    _commit(repo, "2026-10-01T09:00:00+00:00", "reopen")
    _write_features(repo, [_feature("feat-001", "completed")])
    _commit(repo, "2026-10-01T12:30:00+00:00", "complete again")
    monkeypatch.setenv("HARNESS_VERIFY_LAST_REPORT", "")
    for p in (repo / "docs" / "telemetry" / "runs").glob("*.json"):
        p.unlink()
    assert fr.main(args) == 0
    assert _run_record(repo)["gate_runs"]["status"] == "missing"


def test_pending_features_are_the_completed_ones_without_a_summary(repo):
    _write_features(
        repo,
        [
            _feature("feat-001", "completed"),
            _feature("feat-002", "completed", execution_summary={"run_id": "r"}),
            _feature("feat-003", "in_progress"),
        ],
    )
    assert fr.pending_features(repo) == ["feat-001"]


def test_main_exit_codes_and_no_crash_on_hostile_feature_list(repo, tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("CLAUDE_CODE_SESSION_ID", SESSION)
    projects = _projects(tmp_path, [_usage_row("2026-10-01T10:30:00Z", "m1", 10)])
    for text in ("[" * 100000, "null", '"x"', '{"features": 5}', ""):
        (repo / "feature_list.json").write_text(text)
        code = fr.main(["--repo", str(repo), "--projects-dir", str(projects), "--pending"])
        assert code in (0, 2), text[:20]
    assert capsys.readouterr().err is not None


def test_main_without_session_id_exits_2_and_changes_nothing(repo, tmp_path, monkeypatch):
    monkeypatch.delenv("CLAUDE_CODE_SESSION_ID", raising=False)
    _write_features(repo, [_feature("feat-001", "completed")])
    before = (repo / "feature_list.json").read_text()
    assert fr.main(["--repo", str(repo), "--projects-dir", str(tmp_path), "--pending"]) == 2
    assert (repo / "feature_list.json").read_text() == before


def _over_budget_repo(
    repo: Path, feats: list[dict[str, Any]], refs: list[str] | None = None
) -> None:
    _write_features(repo, feats, refs)
    (repo / "PROGRESS.md").write_text("# p\n")


def test_archive_never_loses_a_feature_without_an_id(repo):
    feats = [_feature(f"feat-{i:03d}", "completed", description="d" * 400) for i in range(1, 5)]
    feats.insert(1, {"status": "done", "evidence": "ok", "description": "d" * 400})
    _over_budget_repo(repo, feats)
    fr.archive_to_budget(repo, token_budget=200)
    data = json.loads((repo / "feature_list.json").read_text())
    kept = [f for f in data["features"]]
    archived = [
        f
        for ref in data["archive_references"]
        for f in json.loads((repo / ref).read_text())["features"]
    ]
    assert len(kept) + len(archived) == len(feats)
    lone = {"status": "done", "evidence": "ok", "description": "d" * 400}
    assert lone in kept or lone in archived


def test_archive_file_name_cannot_leave_the_repo(repo, tmp_path):
    hostile = "x/" + "../" * 5 + "escape-marker"
    feats = [
        _feature(hostile, "completed", description="d" * 800),
        _feature("feat-002", "completed", description="d" * 800),
    ]
    _over_budget_repo(repo, feats)
    fr.archive_to_budget(repo, token_budget=10)
    outside = [p for p in tmp_path.rglob("*escape-marker*") if not str(p).startswith(str(repo))]
    assert not outside, outside
    for p in repo.rglob("*"):
        assert str(p.resolve()).startswith(str(repo.resolve()))


def test_archive_never_overwrites_an_existing_archive_file_or_duplicates_a_reference(repo):
    old = repo / "docs" / "archive" / "features" / "archive-feat-001-001.json"
    old.parent.mkdir(parents=True)
    old.write_text(json.dumps({"features": [_feature("feat-001", "completed", name="OLD")]}))
    feats = [
        _feature("feat-001", "completed", description="d" * 800),
        _feature("feat-002", "in_progress", description="d" * 8),
    ]
    _over_budget_repo(repo, feats, refs=["docs/archive/features/archive-feat-001-001.json"])
    moved = fr.archive_to_budget(repo, token_budget=300)
    assert moved == ["feat-001"]
    assert json.loads(old.read_text())["features"][0]["name"] == "OLD"
    refs = json.loads((repo / "feature_list.json").read_text())["archive_references"]
    assert len(refs) == len(set(refs)) == 2


def test_archive_failure_while_replacing_the_main_file_loses_nothing(repo, monkeypatch):
    feats = [_feature(f"feat-{i:03d}", "completed", description="d" * 400) for i in range(1, 6)]
    _over_budget_repo(repo, feats)
    original = (repo / "feature_list.json").read_text()

    def boom(src, dst):
        raise OSError("disk full")

    monkeypatch.setattr(fr.os, "replace", boom)
    with pytest.raises(OSError):
        fr.archive_to_budget(repo, token_budget=10)
    assert (repo / "feature_list.json").read_text() == original
    archive_dir = repo / "docs" / "archive" / "features"
    written = list(archive_dir.glob("*.json"))
    assert written, "the archive is written before the main file is touched"
    held = [f["id"] for p in written for f in json.loads(p.read_text())["features"]]
    assert set(held) <= {f["id"] for f in feats}


def test_archive_ignores_non_dict_entries_and_extra_top_level_keys(repo):
    feats = [_feature(f"feat-{i:03d}", "completed", description="d" * 400) for i in range(1, 5)]
    data = {"archive_references": [], "features": ["junk", 5, None, *feats], "owner": "keep me"}
    (repo / "feature_list.json").write_text(json.dumps(data))
    (repo / "PROGRESS.md").write_text("# p\n")
    fr.archive_to_budget(repo, token_budget=10)
    out = json.loads((repo / "feature_list.json").read_text())
    assert out["owner"] == "keep me" and "junk" in out["features"] and 5 in out["features"]


def test_features_completed_in_one_commit_each_get_a_summary(repo, tmp_path):
    _write_features(
        repo, [_feature("feat-001", "in_progress"), _feature("feat-002", "in_progress")]
    )
    _commit(repo, "2026-10-01T10:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed"), _feature("feat-002", "completed")])
    _commit(repo, "2026-10-01T12:00:00+00:00")
    projects = _projects(tmp_path, [_usage_row("2026-10-01T11:00:00Z", "m1", 10)])
    a = fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)
    b = fr.record_feature(repo, "feat-002", SESSION, projects, outside_log=None)
    data = {f["id"]: f for f in json.loads((repo / "feature_list.json").read_text())["features"]}
    assert a["status"] == "recorded" and b["status"] == "recorded"
    assert (
        data["feat-002"]["execution_summary"]["run_id"]
        == data["feat-001"]["execution_summary"]["run_id"]
    )
    assert data["feat-002"]["execution_summary"].get("shared_with") == "feat-001"
    assert data["feat-002"]["execution_summary"]["output_tokens"] is None


def test_a_feature_without_activity_does_not_move_the_next_window_start(repo, tmp_path):
    _write_features(repo, [_feature("feat-001", "completed")])
    _commit(repo, "2026-10-01T09:00:00+00:00")
    _write_features(repo, [_feature("feat-001", "completed"), _feature("feat-002", "completed")])
    _commit(repo, "2026-10-01T12:00:00+00:00")
    projects = _projects(
        tmp_path,
        [_usage_row("2026-10-01T10:00:00Z", "m1", 7), _usage_row("2026-10-01T11:00:00Z", "m2", 5)],
    )
    assert (
        fr.record_feature(repo, "feat-001", SESSION, projects, outside_log=None)["status"]
        == "no activity"
    )
    out = fr.record_feature(repo, "feat-002", SESSION, projects, outside_log=None)
    assert out["status"] == "recorded"
    data = {f["id"]: f for f in json.loads((repo / "feature_list.json").read_text())["features"]}
    assert data["feat-002"]["execution_summary"]["output_tokens"] == 12


def test_a_hostile_session_id_or_projects_dir_never_writes_outside_the_repo(
    repo, tmp_path, monkeypatch
):
    _write_features(repo, [_feature("feat-001", "completed")])
    _commit(repo, "2026-10-01T12:00:00+00:00")
    for sid in ("../../x", "*", "", "not-a-uuid"):
        monkeypatch.setenv("CLAUDE_CODE_SESSION_ID", sid)
        assert fr.main(["--repo", str(repo), "--projects-dir", str(tmp_path), "--pending"]) == 2


def test_archive_stops_only_when_the_written_file_is_really_within_budget(repo):
    for n, delta in ((10, 0), (10, 1), (12, 7), (20, 15)):
        d = repo.parent / f"r{n}_{delta}"
        d.mkdir()
        feats = [
            _feature(f"feat-{i:03d}", "completed", evidence="e" * 200) for i in range(1, n + 1)
        ]
        _write_features(d, feats)
        (d / "PROGRESS.md").write_text("p" * 100)
        budget = fr.state_tokens(d) - delta - 1
        fr.archive_to_budget(d, token_budget=budget)
        left = [
            f
            for f in json.loads((d / "feature_list.json").read_text())["features"]
            if f["status"] == "completed"
        ]
        assert fr.state_tokens(d) <= budget or not left, (n, delta, fr.state_tokens(d), budget)


def test_archive_survives_a_very_long_feature_id(repo):
    feats = [
        _feature("feat-" + "a" * 400, "completed", description="d" * 400),
        _feature("k", "completed", description="d" * 400),
    ]
    _write_features(repo, feats)
    (repo / "PROGRESS.md").write_text("# p\n")
    moved = fr.archive_to_budget(repo, token_budget=60)
    assert moved
    for p in (repo / "docs" / "archive" / "features").glob("*.json"):
        assert len(p.name) <= 120


def test_archive_does_not_empty_the_feature_list_when_progress_alone_is_over_budget(repo):
    feats = [_feature(f"feat-{i:03d}", "completed") for i in range(1, 6)]
    _write_features(repo, feats)
    (repo / "PROGRESS.md").write_text("p" * 40000)
    before = (repo / "feature_list.json").read_text()
    assert fr.archive_to_budget(repo, token_budget=6000) == []
    assert (repo / "feature_list.json").read_text() == before
    assert not list((repo / "docs").glob("**/*.json")) if (repo / "docs").exists() else True
