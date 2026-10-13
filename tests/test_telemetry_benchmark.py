from __future__ import annotations

import json
import shutil
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import telemetry_benchmark as tb

BENCH = tb.BENCH
SUITE = tb.load_suite()
TASKS = {t["id"]: t for t in SUITE["tasks"]}
REVIEW = (BENCH / "reference" / "B3" / "review.txt").read_text(encoding="utf-8")
FAKE_AGENT = REPO_ROOT / "tests" / "fixtures" / "bench_fake_agent.py"


def _prepared(tmp_path: Path, tid: str) -> Path:
    wd = tmp_path / tid
    tb.prepare(TASKS[tid], wd)
    return wd


def _apply_reference(tid: str, wd: Path) -> None:
    ref = BENCH / "reference" / tid
    if ref.is_dir():
        shutil.copytree(ref, wd, dirs_exist_ok=True)
        tb.restore_names(wd)


def _score(tid: str, wd: Path, text: str = "", rows: list[dict[str, Any]] | None = None):
    return tb.score(TASKS[tid], wd, final_text=text, outside_rows=rows or [])


@pytest.mark.parametrize("tid", ["B1", "B2", "B5"])
def test_unmodified_fixture_fails_and_reference_passes(tmp_path, tid):
    wd = _prepared(tmp_path / "before", tid)
    assert not all(_score(tid, wd).values())
    wd2 = _prepared(tmp_path / "after", tid)
    _apply_reference(tid, wd2)
    result = _score(tid, wd2)
    assert all(result.values()), result


def test_b3_reference_review_passes_and_empty_review_fails(tmp_path):
    wd = _prepared(tmp_path, "B3")
    assert all(_score("B3", wd, REVIEW).values())
    assert not any(
        v for k, v in _score("B3", wd, "Looks fine to me.").items() if k != "no_files_changed"
    )


@pytest.mark.parametrize(
    "missing_defect, key",
    [
        ("mapfile", "found_portability_defect"),
        ("off-by-one", "found_logic_defect"),
        ("no test covers", "found_test_gap"),
    ],
)
def test_b3_each_defect_is_scored_separately(tmp_path, missing_defect, key):
    lines = [ln for ln in REVIEW.splitlines() if missing_defect not in ln]
    wd = _prepared(tmp_path, "B3")
    result = _score("B3", wd, "\n".join(lines))
    assert result[key] is False
    assert sum(1 for k, v in result.items() if k.startswith("found_") and v) == 2


def test_b3_review_that_edits_a_file_fails(tmp_path):
    wd = _prepared(tmp_path, "B3")
    (wd / "paginate.py").write_text("changed\n")
    assert _score("B3", wd, REVIEW)["no_files_changed"] is False


def test_b1_editing_the_tests_fails_even_if_code_is_fixed(tmp_path):
    wd = _prepared(tmp_path, "B1")
    _apply_reference("B1", wd)
    (wd / "test_stats.py").write_text("def test_x():\n    assert True\n")
    r = _score("B1", wd)
    assert r["tests_untouched"] is False and r["only_stats_changed"] is False


def test_b2_adding_tests_to_the_existing_file_is_allowed(tmp_path):
    wd = _prepared(tmp_path, "B2")
    _apply_reference("B2", wd)
    with open(wd / "test_greeter.py", "a") as fh:
        fh.write("\n\ndef test_extra():\n    assert True\n")
    assert all(_score("B2", wd).values())


def test_b2_breaking_existing_behavior_fails_even_if_the_agent_edits_its_tests(tmp_path):
    wd = _prepared(tmp_path, "B2")
    _apply_reference("B2", wd)
    cli = (wd / "cli.py").read_text()
    (wd / "cli.py").write_text(cli.replace('"Hello"', '"Howdy"'))
    (wd / "test_greeter.py").write_text("def test_x():\n    assert True\n")
    assert _score("B2", wd)["original_tests_pass"] is False


def test_b2_fix_without_readme_fails(tmp_path):
    wd = _prepared(tmp_path, "B2")
    _apply_reference("B2", wd)
    shutil.copy(BENCH / "fixtures/B2/README.md", wd / "README.md")
    r = _score("B2", wd)
    assert r["readme_documents_option"] is False and r["hidden_tests_pass"] is True


def test_b2_config_must_accept_any_case_and_false(tmp_path):
    wd = _prepared(tmp_path, "B2")
    _apply_reference("B2", wd)
    cli = (wd / "cli.py").read_text()
    (wd / "cli.py").write_text(cli.replace('.lower() == "true"', '== "true"'))
    assert _score("B2", wd)["hidden_tests_pass"] is False


def test_b5_deleting_features_to_fit_budget_fails(tmp_path):
    wd = _prepared(tmp_path, "B5")
    data = json.loads((wd / "feature_list.json").read_text())
    data["features"] = [f for f in data["features"] if f["id"] in ("feat-001", "feat-900")]
    for f in data["features"]:
        if f["id"] == "feat-900":
            f.update(status="done", evidence="ok")
    (wd / "feature_list.json").write_text(json.dumps(data, indent=2) + "\n")
    (wd / "PROGRESS.md").write_text("# Progress\n- feat-900 done\n")
    r = _score("B5", wd)
    assert r["no_features_lost"] is False and r["within_budget"] is True


def test_b5_marking_done_without_trimming_exceeds_budget(tmp_path):
    wd = _prepared(tmp_path, "B5")
    data = json.loads((wd / "feature_list.json").read_text())
    for f in data["features"]:
        if f["id"] == "feat-900":
            f.update(status="done", evidence="tests pass")
    (wd / "feature_list.json").write_text(json.dumps(data, indent=2) + "\n")
    with open(wd / "PROGRESS.md", "a") as fh:
        fh.write("- feat-900: done\n")
    r = _score("B5", wd)
    assert r["within_budget"] is False and r["feat900_done_with_evidence"] is True


def test_b4_requires_an_independent_successful_outside_run(tmp_path):
    wd = _prepared(tmp_path, "B3")
    good = [{"independent": True, "exit_code": 0}]
    assert all(_score("B4", wd, "review text", good).values())
    for rows in (
        [],
        [{"independent": False, "exit_code": 3}],
        [{"independent": True, "exit_code": 2}],
    ):
        assert _score("B4", wd, "review text", rows)["outside_run_independent"] is False
    assert _score("B4", wd, "  ", good)["review_non_empty"] is False


def test_outside_rows_are_limited_to_the_run_window(tmp_path):
    log = tmp_path / "log.jsonl"
    old = {"timestamp": "2020-01-01T00:00:00+00:00", "independent": True, "exit_code": 0}
    new = {"timestamp": datetime.now(UTC).isoformat(), "independent": True, "exit_code": 0}
    log.write_text(json.dumps(old) + "\n" + json.dumps(new) + "\n")
    rows = tb.outside_rows_since(datetime(2026, 1, 1, tzinfo=UTC), log)
    assert rows == [new]


def test_suite_hash_changes_when_a_fixture_changes(tmp_path):
    bench = tmp_path / "b"
    shutil.copytree(BENCH, bench, ignore=tb.IGNORE)
    before = tb.suite_hash(bench)
    assert before == tb.suite_hash(bench)
    (bench / "fixtures/B1/stats.py.fixture").write_text("x = 1\n")
    assert tb.suite_hash(bench) != before


def test_run_one_with_fake_agent_records_pass_and_fail(tmp_path):
    out = tb.run_one(
        TASKS["B1"],
        agent_cmd=[sys.executable, str(FAKE_AGENT), "apply"],
        outside_log=tmp_path / "none.jsonl",
    )
    assert out["passed"] is True and out["first_pass"] is True and out["telemetry"] is None
    assert out["human_interventions"]["status"] == "measured"
    assert out["gate_failures"]["status"] == "missing"
    bad = tb.run_one(
        TASKS["B1"],
        agent_cmd=[sys.executable, str(FAKE_AGENT), "noop"],
        outside_log=tmp_path / "none.jsonl",
    )
    assert bad["passed"] is False and bad["checks"]["hidden_tests_pass"] is False


def test_agent_timeout_is_a_failed_run_not_a_crash(tmp_path):
    out = tb.run_one(
        TASKS["B1"],
        agent_cmd=[sys.executable, str(FAKE_AGENT), "sleep"],
        timeout=1,
        outside_log=tmp_path / "none.jsonl",
    )
    assert out["passed"] is False and out["agent"]["timed_out"] is True


def _result(
    task: str, commit: str, parent_out: int | None, first_pass: bool, n: int, model="m1", suite="s"
):
    tokens = {
        "output_tokens_sum": {
            "value": parent_out,
            "status": "measured" if parent_out is not None else "missing",
        }
    }
    return {
        "task_id": task,
        "harness_commit": commit,
        "model": model,
        "suite_hash": suite,
        "first_pass": first_pass,
        "checks": {},
        "run_id": f"{task}-{commit}-{n}",
        "telemetry": {
            "parent": {"tokens": tokens},
            "subagents": [],
            "wall_time_ms": {"value": 1000 * (n + 1), "status": "measured"},
        },
    }


def test_compare_needs_five_runs_per_version():
    runs = [_result("B1", "a", 100 + i, True, i) for i in range(4)] + [
        _result("B1", "b", 900 + i, True, i) for i in range(5)
    ]
    assert tb.compare(runs)[0]["parent_out"] == "insufficient runs"


def test_compare_calls_a_difference_only_when_ranges_do_not_overlap():
    a = [_result("B1", "a", 100 + i, True, i) for i in range(5)]
    b = [_result("B1", "b", 900 + i, True, i) for i in range(5)]
    assert tb.compare(a + b)[0]["parent_out"] == "B higher"
    c = [_result("B1", "b", 103 + i, True, i) for i in range(5)]
    assert tb.compare(a + c)[0]["parent_out"] == "no real difference"


def test_compare_with_a_missing_metric_is_na_not_a_number():
    a = [_result("B1", "a", 100 + i, True, i) for i in range(5)]
    b = [_result("B1", "b", None if i == 2 else 900, True, i) for i in range(5)]
    assert tb.compare(a + b)[0]["parent_out"] == "n/a"


def test_compare_never_mixes_models_or_suite_versions():
    a = [_result("B1", "a", 100, True, i) for i in range(5)]
    b = [_result("B1", "b", 900, True, i, model="m2") for i in range(5)]
    c = [_result("B1", "c", 900, True, i, suite="other") for i in range(5)]
    assert tb.compare(a + b + c) == []


def test_first_pass_rate_is_compared():
    a = [_result("B1", "a", 100, True, i) for i in range(5)]
    b = [_result("B1", "b", 100, False, i) for i in range(5)]
    assert tb.compare(a + b)[0]["first_pass_rate"] == "B lower"


def test_planted_shell_defect_is_stored_without_a_sh_suffix_and_restored_for_the_run(tmp_path):
    assert not list(BENCH.rglob("*.sh")) and not list(BENCH.rglob("*.py"))
    wd = _prepared(tmp_path, "B3")
    assert "mapfile" in (wd / "collect.sh").read_text()
    assert not (wd / "collect.sh.fixture").exists()


def test_run_telemetry_counts_only_outside_attempts_made_during_the_run(tmp_path, monkeypatch):
    log = tmp_path / "log.jsonl"
    old = {"timestamp": "2020-01-01T00:00:00+00:00", "attempt": True, "result": "ok"}
    log.write_text(json.dumps(old) + "\n" + json.dumps(old) + "\n")
    session = tmp_path / "sess.jsonl"
    monkeypatch.setenv("FAKE_LOG", str(log))
    monkeypatch.setenv("FAKE_SESSION", str(session))
    monkeypatch.setattr(tb, "find_session", lambda _sid: session)
    quiet = tb.run_one(
        TASKS["B1"], agent_cmd=[sys.executable, str(FAKE_AGENT), "log"], outside_log=log
    )
    t = quiet["telemetry"]
    assert t["outside_agent"]["attempts_logged"]["value"] == 1
    assert t["parent"]["tokens"]["output_tokens_sum"]["value"] == 7
    again = tb.run_one(
        TASKS["B1"], agent_cmd=[sys.executable, str(FAKE_AGENT), "log"], outside_log=log
    )
    assert again["telemetry"]["outside_agent"]["attempts_logged"]["value"] == 1


def test_first_pass_uses_per_run_ranges_so_one_failure_is_not_a_real_difference():
    a = [_result("B1", "a", 100, True, i) for i in range(5)]
    b = [_result("B1", "b", 100, i != 0, i) for i in range(5)]
    assert tb.compare(a + b)[0]["first_pass_rate"] == "no real difference"


def test_first_pass_all_fail_against_all_pass_is_a_real_difference():
    a = [_result("B1", "a", 100, True, i) for i in range(5)]
    b = [_result("B1", "b", 100, False, i) for i in range(5)]
    assert tb.compare(a + b)[0]["first_pass_rate"] == "B lower"


def test_missing_subagents_key_is_missing_not_zero():
    run = {
        "telemetry": {
            "parent": {"tokens": {"output_tokens_sum": {"value": 5, "status": "measured"}}}
        }
    }
    assert tb.run_numbers(run)["sub_out"] is None
    run["telemetry"]["subagents"] = "bad"
    assert tb.run_numbers(run)["sub_out"] is None
    run["telemetry"]["subagents"] = []
    assert tb.run_numbers(run)["sub_out"] == 0.0


def test_real_agent_environment_does_not_expose_hidden_or_reference_directories(monkeypatch):
    seen = {}

    def fake_run(cmd, **kw):
        seen["env"] = kw["env"]

        class R:
            returncode = 0
            stdout = b""

        return R()

    monkeypatch.setattr(tb.subprocess, "run", fake_run)
    tb.run_agent(TASKS["B1"], Path("."), model=None, timeout=5, agent_cmd=None)
    assert "BENCH_DIR" not in seen["env"]
    assert not any(str(BENCH) in str(v) for v in seen["env"].values())


def _git_repo(path: Path) -> Path:
    import subprocess

    path.mkdir(parents=True, exist_ok=True)
    (path / "a.txt").write_text("x\n")
    for cmd in (
        ["git", "init", "-q"],
        ["git", "add", "-A"],
        [
            "git",
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.invalid",
            "commit",
            "-q",
            "-m",
            "m",
        ],
    ):
        subprocess.run(cmd, cwd=path, check=True, capture_output=True)
    return path


def test_harness_commit_ignores_telemetry_output_but_not_real_changes(tmp_path):
    repo = _git_repo(tmp_path / "r")
    clean = tb.harness_commit(repo)
    assert not clean.endswith("-dirty")
    out = repo / "docs" / "telemetry" / "benchmark"
    out.mkdir(parents=True)
    (out / "B1-x.json").write_text("{}\n")
    assert tb.harness_commit(repo) == clean
    (repo / "a.txt").write_text("changed\n")
    assert tb.harness_commit(repo) == clean + "-dirty"


def test_missing_agent_binary_is_a_failed_launch_not_a_crash_and_is_not_compared(tmp_path):
    out = tb.run_one(
        TASKS["B1"], agent_cmd=["/nonexistent/agent"], outside_log=tmp_path / "none.jsonl"
    )
    assert out["passed"] is False and out["agent"]["launch_error"] is True
    runs = [out | {"harness_commit": "a", "model": "m", "suite_hash": "s"} for _ in range(5)]
    assert tb.group_runs(runs) == {}


def test_b1_hard_coded_answer_fails_hidden_tests(tmp_path):
    wd = _prepared(tmp_path, "B1")
    (wd / "stats.py").write_text(
        "def mean(values):\n"
        "    if not values:\n        raise ValueError('x')\n"
        "    return 2 if values == [1, 2, 3] else 0\n\n\n"
        "def median(values):\n"
        "    ordered = sorted(values)\n    mid = len(ordered) // 2\n"
        "    return ordered[mid] if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2\n"
    )
    r = _score("B1", wd)
    assert r["tests_untouched"] is True and r["hidden_tests_pass"] is False


@pytest.mark.parametrize(
    "text",
    [
        "paginate.py has no off-by-one problem. tests have coverage. mapfile works fine on macOS.",
        "paginate is correct and not an off-by-one bug. The tests look fine. mapfile works fine on bash 3.2.",
    ],
)
def test_b3_negated_statements_do_not_count_as_findings(tmp_path, text):
    wd = _prepared(tmp_path, "B3")
    r = _score("B3", wd, text)
    assert not any(v for k, v in r.items() if k.startswith("found_"))


def test_b3_findings_phrased_across_sentences_still_count(tmp_path):
    wd = _prepared(tmp_path, "B3")
    text = (
        "In paginate.py the end index is clamped to len(items) - 1. This drops the last item.\n"
        "test_paginate.py never exercises the last page.\n"
        "collect.sh uses mapfile, which does not exist in the bash 3.2 that ships with macOS."
    )
    assert all(v for k, v in _score("B3", wd, text).items() if k.startswith("found_"))


def test_b5_stripping_old_features_to_fit_the_budget_fails(tmp_path):
    wd = _prepared(tmp_path, "B5")
    data = json.loads((wd / "feature_list.json").read_text())
    slim = [
        {"id": f["id"], "status": f["status"], "evidence": f.get("evidence", "x")}
        for f in data["features"]
    ]
    for f in slim:
        if f["id"] == "feat-900":
            f.update(status="done", evidence="ok", verification="python3 -m pytest -q")
    (wd / "feature_list.json").write_text(json.dumps({"features": slim}, indent=2) + "\n")
    (wd / "PROGRESS.md").write_text("# Progress\n- feat-900 done\n")
    r = _score("B5", wd)
    assert r["no_features_lost"] is False


@pytest.mark.parametrize(
    "text, key",
    [
        (
            "The paginate function works fine for full pages but drops the last item on a partial page.",
            "found_logic_defect",
        ),
        (
            "paginate looks correct at first glance, but it drops the final item.",
            "found_logic_defect",
        ),
        (
            "paginate has no off-by-one error, but the clamp len(items) - 1 truncates the last item.",
            "found_logic_defect",
        ),
        ("paginate returns one item too few on the last page.", "found_logic_defect"),
        ("The tests have coverage gaps: the last page is never tested.", "found_test_gap"),
        (
            "mapfile is fine on Linux but not available on macOS bash 3.2.",
            "found_portability_defect",
        ),
    ],
)
def test_b3_real_findings_with_hedges_or_other_wording_count(tmp_path, text, key):
    assert _score("B3", _prepared(tmp_path, "B3"), text)[key] is True


@pytest.mark.parametrize(
    "text, key",
    [
        ("I did not find an off-by-one in paginate.", "found_logic_defect"),
        ("paginate is fine. The collect script drops non-py files.", "found_logic_defect"),
        (
            "paginate is fine. The collect script skips nothing but mapfile is not available on bash 3.2.",
            "found_logic_defect",
        ),
        ("I found nothing wrong with paginate; it does not drop items.", "found_logic_defect"),
    ],
)
def test_b3_evasive_or_cross_subject_text_does_not_count(tmp_path, text, key):
    assert _score("B3", _prepared(tmp_path, "B3"), text)[key] is False


def test_b5_list_root_feature_file_is_a_failed_check_not_a_crash(tmp_path):
    wd = _prepared(tmp_path, "B5")
    (wd / "feature_list.json").write_text("[]\n")
    r = _score("B5", wd)
    assert r["state_layer_valid"] is False or r["within_budget"] is False
    assert r["no_features_lost"] is False


def test_agent_output_that_is_not_utf8_is_a_failed_run_not_a_crash(tmp_path):
    out = tb.run_one(
        TASKS["B1"],
        agent_cmd=["sh", "-c", "printf '\\377\\376'"],
        outside_log=tmp_path / "none.jsonl",
    )
    assert out["passed"] is False


def test_non_utf8_agent_written_files_are_failed_checks_not_crashes(tmp_path):
    wd = _prepared(tmp_path / "b5", "B5")
    _apply_reference("B5", wd)
    (wd / "PROGRESS.md").write_bytes(b"\xff\xfe feat-900")
    assert _score("B5", wd)["progress_updated"] is True
    wd2 = _prepared(tmp_path / "b2", "B2")
    _apply_reference("B2", wd2)
    (wd2 / "README.md").write_bytes(b"\xff\xfe --shout shout = true")
    assert _score("B2", wd2)["readme_documents_option"] is True


def test_harness_commit_ignores_all_telemetry_output(tmp_path):
    repo = _git_repo(tmp_path / "r2")
    clean = tb.harness_commit(repo)
    for sub in ("runs", "benchmark"):
        d = repo / "docs" / "telemetry" / sub
        d.mkdir(parents=True, exist_ok=True)
        (d / "x.json").write_text("{}\n")
    (repo / "docs" / "telemetry" / "evaluation-trace.jsonl").write_text("{}\n")
    assert tb.harness_commit(repo) == clean
