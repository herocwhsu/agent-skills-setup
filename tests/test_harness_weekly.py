"""harness_weekly.py: the weekly evaluation of every target repo, silent unless worse."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import harness_weekly as hw

UPDATE_OK = """==> Detecting outside agents...
[outside-agent] conf matches detection
==> Syncing target repos (harness_adapter.py sync-all)...
  /r/hangar: up to date
  /r: workspace: up to date
"""


def _audit(tokens: int = 4000, drifted: tuple[str, ...] = ()) -> dict[str, Any]:
    hooks = [{"file": "ok.sh", "status": "identical"}] + [
        {"file": h, "status": "drifted"} for h in drifted
    ]
    return {"always_loaded": {"tokens": tokens}, "hooks": hooks}


def test_a_clean_week_has_no_regressions() -> None:
    assert hw.update_regressions(UPDATE_OK, 0) == []
    assert hw.repo_regressions("hangar", _audit(), _audit(4300), {"result": "pass"}) == []


def test_update_failures_and_agent_changes_are_regressions() -> None:
    log = UPDATE_OK.replace(
        "[outside-agent] conf matches detection",
        "[outside-agent] detected but not listed: codex; listed but not found: agy",
    ).replace("/r/hangar: up to date", "/r/hangar: error: agent-harness.json: bad key")
    log += "ERROR: git pull failed (possible diverged branch or network issue).\n"
    found = hw.update_regressions(log, 1)
    assert found == [
        "update.sh failed (exit 1): ERROR: git pull failed (possible diverged branch or network issue).",
        "new agent detected: codex; add it to ~/.agent-skills-setup/outside-agents.conf where it should rank",
        "listed agent not answering: agy",
        "sync failed: /r/hangar: error: agent-harness.json: bad key",
    ]
    assert hw.update_regressions(
        UPDATE_OK.replace("/r/hangar: up to date", "/r/hangar: missing"), 0
    ) == ["sync failed: /r/hangar: missing"]
    # outside_agent.py joins several names with spaces
    many = (
        "[outside-agent] detected but not listed: codex kiro; listed but not found: gemini claude"
    )
    assert hw.update_regressions(many, 0) == [
        (
            "new agent detected: codex kiro; add it to "
            "~/.agent-skills-setup/outside-agents.conf where it should rank"
        ),
        "listed agent not answering: gemini claude",
    ]
    # sync-all crashing outright: update.sh swallows it into a WARN line and exits 0
    crash = (
        UPDATE_OK
        + "Traceback (most recent call last):\n  WARN  a registered target repo is missing or failed to sync (see above)\n"
    )
    assert hw.update_regressions(crash, 0) == [
        "sync failed: WARN  a registered target repo is missing or failed to sync (see above)"
    ]


def test_repo_regressions_drift_token_growth_and_a_failed_last_verify() -> None:
    found = hw.repo_regressions(
        "atelier",
        _audit(4000),
        _audit(4500, drifted=("ts-guard.sh",)),
        {"result": "fail", "commit": "abc1234", "ts": "2026-10-19T09:00:00+08:00"},
    )
    assert found == [
        "atelier: hook drifted from its template: ts-guard.sh",
        "atelier: always-loaded tokens 4000 -> 4500 (+12%)",
        "atelier: last verify run failed (abc1234, 2026-10-19)",
    ]
    # first audit ever, no verify run yet: nothing to compare, nothing to report
    assert hw.repo_regressions("atelier", None, _audit(9000), None) == []


def _runtime(tmp_path: Path) -> tuple[Path, Path]:
    runtime, repo = tmp_path / "rt", tmp_path / "work/hangar"
    repo.mkdir(parents=True)
    runtime.mkdir()
    (runtime / "target-repos.txt").write_text(f"{repo}\n")
    prev = runtime / "audits/hangar/2026-10-12.json"
    prev.parent.mkdir(parents=True)
    prev.write_text(json.dumps(_audit(4000)))
    log = runtime / "telemetry/hangar/verify-runs-202610.jsonl"
    log.parent.mkdir(parents=True)
    log.write_text(
        json.dumps({"ts": "2026-10-18T09:00:00+08:00", "result": "fail", "commit": "old"})
        + "\n"
        + json.dumps({"ts": "2026-10-19T08:00:00+08:00", "result": "pass", "commit": "new"})
        + "\n"
    )
    return runtime, repo


def test_real_audit_shape_reports_a_drifted_hook(tmp_path: Path) -> None:
    import repo_audit

    repo, templates = tmp_path / "repo", tmp_path / "templates"
    (templates / "common").mkdir(parents=True)
    (templates / "common/x.sh").write_text("#!/bin/bash\necho template\n")
    (repo / ".claude/hooks").mkdir(parents=True)
    (repo / ".claude/hooks/x.sh").write_text("#!/bin/bash\necho changed\n")
    (repo / "agent-harness.json").write_text(
        json.dumps({"hooks": [{"template": "common/x.sh", "event": "edit"}]})
    )
    cur = repo_audit.audit(repo, tmp_path / "home", templates)
    assert hw.repo_regressions("r", None, cur, None) == ["r: hook drifted from its template: x.sh"]


def test_run_flags_a_repo_left_with_uncommitted_changes(tmp_path: Path) -> None:
    # sync never commits: a template change leaves the copies for someone to review
    runtime, repo = _runtime(tmp_path)
    _git(repo, "init", "-q")
    _commit(repo, "AGENTS.md", "2026-10-18T10:00:00+08:00")
    _commit(repo, ".claude/hooks/x.sh", "2026-10-18T10:00:00+08:00")
    # the owner's own work in progress is not sync's and is not reported
    (repo / "AGENTS.md").write_text("owner editing")
    (repo / "notes.txt").write_text("new")
    (repo / ".claude/hooks/x.sh").write_text("edited by sync")
    _, found = hw.run(
        runtime, UPDATE_OK, 0, today="2026-10-19", audit_fn=lambda r: _audit(4100), extra_repos=()
    )
    assert found == [
        "hangar: uncommitted changes after sync, commit or revert them: .claude/hooks/x.sh"
    ]


def test_run_saves_this_weeks_audit_and_reports_against_last_weeks(tmp_path: Path) -> None:
    runtime, _ = _runtime(tmp_path)
    report, found = hw.run(
        runtime, UPDATE_OK, 0, today="2026-10-19", audit_fn=lambda r: _audit(4100)
    )
    assert found == []
    assert json.loads((runtime / "audits/hangar/2026-10-19.json").read_text()) == _audit(4100)
    assert "No regressions." in report and "| hangar |" in report
    # the latest verify run decides, not an earlier failure in the week
    _, found = hw.run(runtime, UPDATE_OK, 0, today="2026-10-19", audit_fn=lambda r: _audit(5000))
    assert found == ["hangar: always-loaded tokens 4000 -> 5000 (+25%)"]


def test_main_writes_the_report_and_exits_1_only_on_regressions(tmp_path: Path) -> None:
    runtime, _ = _runtime(tmp_path)
    log, out = tmp_path / "update.log", tmp_path / "out/report.md"
    log.write_text(UPDATE_OK)
    args = ["--runtime", str(runtime), "--update-log", str(log), "--update-rc", "0"]
    assert hw.main([*args, "--out", str(out), "--today", "2026-10-19"]) in (0, 1)
    assert out.read_text().startswith("# Harness weekly 2026-10-19")
    log.write_text(UPDATE_OK + "ERROR: boom\n")
    assert hw.main([*args, "--update-rc", "3", "--out", str(out), "--today", "2026-10-19"]) == 1
    assert "update.sh failed (exit 3): ERROR: boom" in out.read_text()


def _git(repo: Path, *args: str, date: str | None = None) -> None:
    import os
    import subprocess

    env = {
        **os.environ,
        "GIT_AUTHOR_NAME": "dev",
        "GIT_AUTHOR_EMAIL": "d@example.com",
        "GIT_COMMITTER_NAME": "dev",
        "GIT_COMMITTER_EMAIL": "d@example.com",
    }
    if date:
        env |= {"GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    subprocess.run(["git", "-C", str(repo), *args], check=True, env=env, capture_output=True)


def _commit(repo: Path, path: str, date: str, author: str = "dev", msg: str | None = None) -> None:
    f = repo / path
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(date)
    _git(repo, "add", "-A")
    _git(
        repo,
        "-c",
        f"user.name={author}",
        "commit",
        "-q",
        "--author",
        f"{author} <a@example.com>",
        "-m",
        msg or path,
        date=date,
    )


def test_review_coverage_counts_risky_commits_and_matching_outside_reviews(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    _commit(repo, "docs/a.md", "2026-10-13T10:00:00+08:00")  # not risky
    _commit(repo, ".claude/hooks/x.sh", "2026-10-14T10:00:00+08:00")  # reviewed next day
    _commit(repo, "scripts/install.sh", "2026-10-15T10:00:00+08:00")  # never reviewed
    _commit(repo, ".github/workflows/ci.yml", "2026-10-16T10:00:00+08:00", author="renovate[bot]")
    runs = [
        {
            "purpose": "review",
            "repo": str(repo),
            "exit_code": 0,
            "timestamp": "2026-10-15T01:00:00+00:00",
        },
        {
            "purpose": "review",
            "repo": "/elsewhere",
            "exit_code": 0,
            "timestamp": "2026-10-16T01:00:00+00:00",
        },
        {
            "purpose": "delegate",
            "repo": str(repo),
            "exit_code": 0,
            "timestamp": "2026-10-16T01:00:00+00:00",
        },
    ]
    since = hw._parse_ts("2026-10-12T00:00:00+08:00")
    c = hw.review_coverage(repo, runs, since)
    assert (c["risky"], c["reviewed"]) == (2, 1)
    assert [u.split(" ", 1)[1] for u in c["unreviewed"]] == ["scripts/install.sh"]
    # a failed review run is no review
    runs[0]["exit_code"] = 2
    assert hw.review_coverage(repo, runs, since)["reviewed"] == 0


def test_rework_counts_fixes_to_code_another_commit_changed_in_the_48h_before(
    tmp_path: Path,
) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    # Before the window, but inside 48 h of the first fix: still the code it reworks.
    _commit(repo, "scripts/a.py", "2026-10-14T10:00:00+08:00", msg="feat: a")
    _commit(repo, "docs/a.md", "2026-10-14T11:00:00+08:00", msg="docs: a")
    _commit(repo, "scripts/a.py", "2026-10-15T09:00:00+08:00", msg="fix: a again")  # rework
    _commit(repo, "scripts/b.py", "2026-10-15T10:00:00+08:00", msg="fix(b): new bug")  # first touch
    _commit(repo, "docs/a.md", "2026-10-15T11:00:00+08:00", msg="fix: typo")  # docs only
    _commit(repo, "scripts/c.py", "2026-10-15T12:00:00+08:00", msg="feat: c")
    _commit(repo, "scripts/c.py", "2026-10-18T13:00:00+08:00", msg="fix: c")  # 73 h later
    _commit(
        repo,
        "scripts/a.py",
        "2026-10-16T09:00:00+08:00",
        author="renovate[bot]",
        msg="fix(deps): a",
    )
    r = hw.rework(repo, hw._parse_ts("2026-10-15T00:00:00+08:00"))
    assert (r["fixes"], r["rework"]) == (4, 1)
    assert [x.split(" ", 1)[1] for x in r["reworked"]] == ["fix: a again"]


def test_run_reports_review_coverage_without_counting_it_as_a_regression(tmp_path: Path) -> None:
    runtime, repo = _runtime(tmp_path)
    _git(repo, "init", "-q")
    _commit(repo, ".claude/hooks/x.sh", "2026-10-18T10:00:00+08:00")
    report, found = hw.run(
        runtime, UPDATE_OK, 0, today="2026-10-19", audit_fn=lambda r: _audit(4100), extra_repos=()
    )
    assert found == []
    assert "## Outside reviews of risky commits" in report
    assert "| hangar | 1 | 0 |" in report
    assert "## Rework" in report
    assert "| hangar | 0 | 0 | - |" in report
