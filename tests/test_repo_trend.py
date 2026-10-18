"""Unit tests for scripts/repo_trend.py."""

from __future__ import annotations

import datetime
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import repo_trend as rt

TODAY = datetime.date(2026, 10, 20)


def _audit(root: Path, repo: str, day: str, tokens: int, drifted: int, agents: list[str]) -> None:
    d = root / repo
    d.mkdir(parents=True, exist_ok=True)
    hooks = [{"file": f"h{i}.sh", "status": "drifted"} for i in range(drifted)]
    hooks.append({"file": "ok.sh", "status": "identical"})
    (d / f"{day}.json").write_text(
        json.dumps(
            {
                "repo": repo,
                "always_loaded": {"tokens": tokens, "skill_tokens_scoped": tokens // 2},
                "state_files": [{"file": "PROGRESS.md", "tokens": 100}],
                "hooks": hooks,
                "agent_hooks": {a: a in agents for a in ("claude", "codex", "agy")},
            }
        )
    )


def _runs(runtime: Path, repo: str, rows: list[tuple[str, str, int]], junk: bool = False) -> None:
    d = runtime / "telemetry" / repo
    d.mkdir(parents=True, exist_ok=True)
    lines = [
        json.dumps({"ts": ts, "repo": repo, "result": r, "duration_s": s}) for ts, r, s in rows
    ]
    if junk:
        lines.append("{not json")
    (d / "verify-runs-202610.jsonl").write_text("\n".join(lines) + "\n")


def test_trend_table(tmp_path: Path) -> None:
    audits, runtime = tmp_path / "repos", tmp_path / "runtime"
    _audit(audits, "hangar", "2026-10-01", 9000, 2, ["claude"])
    _audit(audits, "hangar", "2026-10-15", 5000, 0, ["claude", "codex", "agy"])
    _audit(audits, "hangar", "2026-10-18", 4000, 0, ["claude", "codex", "agy"])
    _runs(
        runtime,
        "hangar",
        [
            ("2026-09-01T10:00:00+08:00", "fail", 999),
            ("2026-10-18T10:00:00+08:00", "pass", 90),
            ("2026-10-18T11:00:00+08:00", "fail", 30),
            ("2026-10-19T10:00:00+08:00", "pass", 100),
        ],
        junk=True,
    )
    _audit(audits, "atelier", "2026-10-18", 3000, 1, ["claude"])
    out = rt.render(audits, runtime, days=7, today=TODAY)
    hangar = next(line for line in out.splitlines() if line.startswith("| hangar"))
    assert "5000 → 4000" in hangar  # window starts 2026-10-13: the 10-01 audit is outside
    assert "3 runs, 1 failed, median 90s, max 100s" in hangar
    atelier = next(line for line in out.splitlines() if line.startswith("| atelier"))
    assert "3000" in atelier and "no verify runs" in atelier
    assert "1" in atelier.split("|")[5]  # drifted hooks column


def test_no_audits(tmp_path: Path) -> None:
    assert "no repo audits" in rt.render(tmp_path / "none", tmp_path, days=7, today=TODAY)


def test_audit_before_window_is_used_when_none_inside(tmp_path: Path) -> None:
    audits = tmp_path / "repos"
    _audit(audits, "old", "2026-09-01", 7000, 0, ["claude"])
    line = next(
        x
        for x in rt.render(audits, tmp_path, days=7, today=TODAY).splitlines()
        if x.startswith("| old")
    )
    assert "7000" in line and "2026-09-01" in line
