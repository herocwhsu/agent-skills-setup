"""Tests for scripts/gate_experiment.py (planted-defect runs over the gate set)."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import gate_experiment as ge

CASES = json.loads((REPO_ROOT / "tests" / "gate_cases" / "cases.json").read_text())["cases"]

FAKE_VERIFY = """#!/usr/bin/env bash
# Fake harness-verify: fails the gate named in $FAKE_FAIL (comma separated), passes the rest.
echo "=== harness verify ==="
for g in registry types tests; do
  if [[ ",${FAKE_FAIL:-}," == *",$g,"* ]]; then echo "  FAIL  $g (exit 2, 5ms)"; else echo "  OK    $g (5ms)"; fi
done
[[ -z "${FAKE_FAIL:-}" ]] && { echo "All gates passed."; exit 0; }
echo "FAILED: ${FAKE_FAIL//,/ }"; exit 1
"""


def _git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@example.invalid", *args],
        check=True,
        capture_output=True,
    )


@pytest.fixture
def fake_repo(tmp_path: Path) -> Path:
    r = tmp_path / "src"
    (r / "scripts").mkdir(parents=True)
    (r / "scripts" / "harness-verify.sh").write_text(FAKE_VERIFY)
    (r / "registry.txt").write_text("# registry\n")
    (r / "feature_list.json").write_text(
        json.dumps({"archive_references": [], "features": []}) + "\n"
    )
    _git(r, "init", "-q")
    _git(r, "add", "-A")
    _git(r, "commit", "-q", "-m", "init")
    return r


def test_shipped_cases_are_well_formed_and_cover_every_gate():
    ids = [c["id"] for c in CASES]
    assert len(ids) == len(set(ids))
    for c in CASES:
        assert c["expect"] in ge.GATES, c
        assert c["ops"] and all(o["op"] in ge.OPS for o in c["ops"]), c
    assert {c["expect"] for c in CASES} == set(ge.GATES)


def test_shipped_cases_contain_no_literal_secret_shapes():
    text = (REPO_ROOT / "tests" / "gate_cases" / "cases.json").read_text()
    import re

    assert not re.search(r"gh[pousr]_[A-Za-z0-9]{20,}", text)
    assert not re.search(r"-----BEGIN [A-Z ]*PRIVATE KEY", text)


def test_ops_write_append_and_json_append_feature(tmp_path):
    d = tmp_path / "w"
    d.mkdir()
    (d / "feature_list.json").write_text(json.dumps({"features": []}))
    ge.apply_ops(d, [{"op": "write", "path": "a/b.txt", "text": "x"}])
    ge.apply_ops(d, [{"op": "append", "path": "a/b.txt", "text": "y"}])
    ge.apply_ops(d, [{"op": "write_joined", "path": "c.txt", "parts": ["a", "b", "c"]}])
    ge.apply_ops(
        d, [{"op": "json_append_feature", "path": "feature_list.json", "feature": {"id": "f1"}}]
    )
    assert (d / "a" / "b.txt").read_text() == "xy"
    assert (d / "c.txt").read_text() == "abc"
    assert json.loads((d / "feature_list.json").read_text())["features"] == [{"id": "f1"}]


@pytest.mark.parametrize("bad", ["../escape.txt", "/etc/passwd", "a/../../x"])
def test_ops_refuse_paths_outside_the_work_tree(tmp_path, bad):
    d = tmp_path / "w"
    d.mkdir()
    with pytest.raises(ValueError):
        ge.apply_ops(d, [{"op": "write", "path": bad, "text": "x"}])
    assert not (tmp_path / "escape.txt").exists()


def test_unknown_op_is_an_error(tmp_path):
    with pytest.raises(ValueError):
        ge.apply_ops(tmp_path, [{"op": "rm_rf", "path": "x"}])


def test_parse_gate_results_reads_ok_fail_and_skip_lines():
    out = (
        "  OK    registry (3ms)\n  FAIL  types (exit 2, 9ms)\n  SKIP  tests (0ms)\nFAILED: types\n"
    )
    assert ge.parse_gate_results(out) == {"registry": "OK", "types": "FAIL", "tests": "SKIP"}


def test_parse_gate_results_handles_multi_word_names_and_noise():
    out = "  OK    skill paths (3ms)\n  FAIL  secret scan (exit 2, 9ms)\n        some indented detail\n"
    assert ge.parse_gate_results(out) == {"skill paths": "OK", "secret scan": "FAIL"}


def test_baseline_must_pass_everywhere(fake_repo, tmp_path):
    res = ge.run_case(
        fake_repo,
        {"id": "base", "expect": "registry", "ops": []},
        tmp_path / "work",
        env={"FAKE_FAIL": ""},
    )
    assert res["failed"] == [] and res["exit"] == 0


def test_run_case_applies_ops_in_a_fresh_clone_and_leaves_the_source_untouched(fake_repo, tmp_path):
    case = {
        "id": "c",
        "expect": "registry",
        "ops": [{"op": "write", "path": "scratch.txt", "text": "x"}],
    }
    res = ge.run_case(fake_repo, case, tmp_path / "work", env={"FAKE_FAIL": "registry"})
    assert res["failed"] == ["registry"]
    assert not (fake_repo / "scratch.txt").exists()
    assert (tmp_path / "work" / "c" / "scratch.txt").exists()


def test_each_case_starts_from_a_clean_clone(fake_repo, tmp_path):
    a = {
        "id": "a",
        "expect": "registry",
        "ops": [{"op": "write", "path": "only_a.txt", "text": "x"}],
    }
    b = {"id": "b", "expect": "registry", "ops": []}
    ge.run_case(fake_repo, a, tmp_path / "work", env={"FAKE_FAIL": ""})
    ge.run_case(fake_repo, b, tmp_path / "work", env={"FAKE_FAIL": ""})
    assert not (tmp_path / "work" / "b" / "only_a.txt").exists()


def test_a_case_whose_expected_gate_does_not_fail_is_marked_broken():
    rows = [{"id": "x", "expect": "types", "failed": ["tests"], "exit": 1}]
    assert ge.analyze(rows)["broken"] == ["x"]


def test_analysis_marks_a_gate_redundant_only_if_every_case_it_catches_is_caught_by_another():
    rows = [
        {"id": "c1", "expect": "types", "failed": ["types", "tests"], "exit": 1},
        {"id": "c2", "expect": "types", "failed": ["types", "tests"], "exit": 1},
        {"id": "c3", "expect": "tests", "failed": ["tests"], "exit": 1},
    ]
    res = ge.analyze(rows)
    assert res["verdict"]["types"] == "possibly redundant"
    assert res["verdict"]["tests"] == "needed"


def test_a_gate_that_is_the_only_one_to_catch_a_case_is_needed():
    rows = [{"id": "c1", "expect": "secret scan", "failed": ["secret scan"], "exit": 1}]
    assert ge.analyze(rows)["verdict"]["secret scan"] == "needed"


def test_a_gate_with_no_case_that_it_catches_is_not_judged():
    rows = [{"id": "c1", "expect": "types", "failed": ["tests"], "exit": 1}]
    res = ge.analyze(rows)
    assert res["verdict"].get("types") == "cannot judge"
    assert res["broken"] == ["c1"]


def test_broken_cases_do_not_count_toward_conclusions():
    rows = [
        {"id": "ok", "expect": "types", "failed": ["types"], "exit": 1},
        {"id": "bad", "expect": "types", "failed": ["tests"], "exit": 1},
    ]
    res = ge.analyze(rows)
    assert res["verdict"]["types"] == "needed"
    assert res["verdict"].get("tests") != "possibly redundant"


def test_collateral_failures_are_reported_per_case():
    rows = [{"id": "c1", "expect": "types", "failed": ["types", "tests"], "exit": 1}]
    assert ge.analyze(rows)["also_caught_by"]["c1"] == ["tests"]


def test_render_table_has_one_row_per_case_and_names_the_failing_gates():
    rows = [
        {"id": "c1", "expect": "registry", "failed": ["registry"], "exit": 1},
        {"id": "c2", "expect": "types", "failed": [], "exit": 0},
    ]
    text = ge.render(rows, ge.analyze(rows))
    assert "c1" in text and "c2" in text and "BROKEN" in text
    assert text.count("\n") >= 4


def test_cli_rejects_an_unknown_case_id(fake_repo, capsys):
    assert ge.main(["--repo", str(fake_repo), "--case", "nope"]) == 2
    assert "nope" in capsys.readouterr().err


def test_cli_never_uses_the_real_home(fake_repo, tmp_path, monkeypatch):
    seen = {}
    real = ge.run_case

    def spy(src, case, work, env=None):
        seen["env"] = env
        return {"id": case["id"], "expect": case["expect"], "failed": [], "exit": 0}

    monkeypatch.setattr(ge, "run_case", spy)
    monkeypatch.setenv("HOME", "/Users/definitely-real")
    ge.main(["--repo", str(fake_repo), "--case", CASES[0]["id"], "--work-dir", str(tmp_path / "w")])
    assert "env" in seen
    assert str(seen["env"]["HOME"]) != "/Users/definitely-real"
    assert real is not spy


def test_gate_names_match_harness_verify_and_runtime_files_match_lib():
    import re

    import _gate_names

    verify = (REPO_ROOT / "scripts" / "harness-verify.sh").read_text()
    printed = re.findall(r'run_gate "([^"]+)"', verify)
    assert list(_gate_names.GATES) == printed
    lib = (REPO_ROOT / "scripts" / "_lib.sh").read_text()
    body = lib.split("runtime_files() {")[1].split("cat <<'EOF'\n")[1].split("\nEOF")[0]
    pairs = [tuple(line.split()) for line in body.splitlines() if line.strip()]
    assert [tuple(p) for p in _gate_names.RUNTIME_FILES] == pairs


def test_a_gate_failing_at_baseline_is_excluded_not_counted_as_catching_everything():
    rows = [
        {"id": "base", "expect": None, "failed": ["types"], "exit": 1},
        {"id": "c1", "expect": "tests", "failed": ["tests", "types"], "exit": 1},
        {"id": "c2", "expect": "registry", "failed": ["registry", "types"], "exit": 1},
    ]
    res = ge.analyze(rows, baseline_failed=["types"])
    assert res["verdict"]["types"] == "cannot judge"
    assert res["verdict"]["tests"] == "needed" and res["verdict"]["registry"] == "needed"
    assert res["also_caught_by"]["c1"] == []


def test_two_gates_that_only_ever_fail_together_are_not_both_called_redundant():
    rows = [{"id": "c1", "expect": "types", "failed": ["types", "tests"], "exit": 1}]
    res = ge.analyze(rows)
    flagged = [g for g in ("types", "tests") if res["verdict"][g] == "possibly redundant"]
    assert len(flagged) == 1


def test_a_chain_of_overlaps_cannot_remove_every_gate_that_catches_a_case():
    rows = [
        {"id": "c1", "expect": "types", "failed": ["types", "tests", "bash compat"], "exit": 1},
        {"id": "c2", "expect": "tests", "failed": ["types", "tests", "bash compat"], "exit": 1},
    ]
    res = ge.analyze(rows)
    flagged = [
        g for g in ("types", "tests", "bash compat") if res["verdict"][g] == "possibly redundant"
    ]
    assert len(flagged) <= 2


def test_cli_runs_a_baseline_first_and_refuses_when_it_is_not_clean(
    fake_repo, tmp_path, capsys, monkeypatch
):
    calls = []

    def fake(src, case, work, env=None):
        calls.append(case["id"])
        failed = ["types"] if case["id"] == ge.BASELINE_ID else []
        return {
            "id": case["id"],
            "expect": case.get("expect"),
            "failed": failed,
            "exit": 1 if failed else 0,
        }

    monkeypatch.setattr(ge, "run_case", fake)
    code = ge.main(
        ["--repo", str(fake_repo), "--case", CASES[0]["id"], "--work-dir", str(tmp_path / "w")]
    )
    assert calls[0] == ge.BASELINE_ID
    assert code == 2 and "baseline" in capsys.readouterr().err.lower()


def test_cli_skips_the_baseline_only_when_asked(fake_repo, tmp_path, monkeypatch):
    calls = []

    def fake(src, case, work, env=None):
        calls.append(case["id"])
        return {"id": case["id"], "expect": case.get("expect"), "failed": [], "exit": 0}

    monkeypatch.setattr(ge, "run_case", fake)
    ge.main(
        [
            "--repo",
            str(fake_repo),
            "--case",
            CASES[0]["id"],
            "--work-dir",
            str(tmp_path / "w"),
            "--no-baseline",
        ]
    )
    assert ge.BASELINE_ID not in calls


def test_the_repo_clone_is_taken_from_the_working_tree_state(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    _git(src, "init", "-q")
    (src / "f.txt").write_text("committed\n")
    _git(src, "add", "-A")
    _git(src, "commit", "-q", "-m", "init")
    (src / "f.txt").write_text("edited but uncommitted\n")
    dst = tmp_path / "dst"
    ge._clone(src, dst)
    assert (dst / "f.txt").read_text() == "edited but uncommitted\n"


def test_planted_python_files_are_tracked_so_the_type_gate_can_see_them(tmp_path):
    src = tmp_path / "src"
    src.mkdir()
    _git(src, "init", "-q")
    (src / "a.txt").write_text("x\n")
    _git(src, "add", "-A")
    _git(src, "commit", "-q", "-m", "init")
    dst = tmp_path / "dst"
    ge._clone(src, dst)
    ge.apply_ops(dst, [{"op": "write", "path": "scripts/x.py", "text": "y = 1\n"}])
    ge.track(dst)
    listed = subprocess.run(
        ["git", "-C", str(dst), "ls-files", "*.py"], capture_output=True, text=True
    ).stdout
    assert "scripts/x.py" in listed


def test_cases_use_real_registry_types_and_random_looking_secret_material():
    by_id = {c["id"]: c for c in CASES}
    reg = "".join(o.get("text", "") for o in by_id["registry-missing-skill"]["ops"])
    assert reg.split()[0] == "local"
    sec = by_id["secret-scan-key-shape"]["ops"][0]
    assert sec["op"] == "write_random"


def test_planted_files_are_staged_only_for_cases_that_ask_for_it(fake_repo, tmp_path):
    plain = {
        "id": "plain",
        "expect": "registry",
        "ops": [{"op": "write", "path": "scratch.txt", "text": "x"}],
    }
    staged = {
        "id": "staged",
        "expect": "types",
        "stage": True,
        "ops": [{"op": "write", "path": "t.py", "text": "x = 1\n"}],
    }
    ge.run_case(fake_repo, plain, tmp_path / "w", env={"FAKE_FAIL": ""})
    ge.run_case(fake_repo, staged, tmp_path / "w", env={"FAKE_FAIL": ""})

    def porcelain(case_id: str) -> str:
        return subprocess.run(
            ["git", "-C", str(tmp_path / "w" / case_id), "status", "--porcelain"],
            capture_output=True,
            text=True,
        ).stdout

    assert "?? scratch.txt" in porcelain("plain")
    assert "A  t.py" in porcelain("staged")


def test_only_the_type_case_asks_to_be_staged():
    staged = [c["id"] for c in CASES if c.get("stage")]
    assert staged == ["types-error"]
