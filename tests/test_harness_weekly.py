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
    hooks = [{"copy": ".claude/hooks/ok.sh", "status": "identical"}] + [
        {"copy": f".claude/hooks/{h}", "status": "drifted"} for h in drifted
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
