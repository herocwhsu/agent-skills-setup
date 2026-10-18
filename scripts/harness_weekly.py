#!/usr/bin/env python3
"""Weekly evaluation of every target repo: silent unless something got worse.

Run after update.sh by hangar's harness-weekly LaunchAgent, with update.sh's output
and exit code. Saves this week's audit of each registered repo to
<runtime>/audits/<repo>/<date>.json (per machine: committing here would make the
next `git pull --ff-only` in update.sh fail once the remote moves), compares it with
the latest earlier one, and writes a markdown report. Exit 1 when the report lists a
regression, 0 when not, 2 when it could not run.

Usage: harness_weekly.py --update-log FILE --update-rc N --out FILE [--days N]
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

import repo_audit
import repo_trend

HARNESS = Path(__file__).resolve().parent.parent
TOKEN_GROWTH = 0.10


def update_regressions(log: str, rc: int) -> list[str]:
    found: list[str] = []
    if rc != 0:
        errors = [ln.strip() for ln in log.splitlines() if ln.strip().startswith("ERROR")]
        found.append(f"update.sh failed (exit {rc}): {errors[-1] if errors else 'no ERROR line'}")
    m = re.search(r"detected but not listed: (\S+); listed but not found: (\S+)", log)
    if m:
        add, gone = m.group(1), m.group(2)
        if add != "-":
            found.append(
                f"new agent detected: {add}; add it to "
                "~/.agent-skills-setup/outside-agents.conf where it should rank"
            )
        if gone != "-":
            found.append(f"listed agent not answering: {gone}")
    found += [
        f"sync failed: {ln.strip()}"
        for ln in log.splitlines()
        if re.match(r"^\s+\S+: (error: |missing$)", ln)
    ]
    return found


def repo_regressions(
    repo: str, prev: dict[str, Any] | None, cur: dict[str, Any], last_verify: dict[str, Any] | None
) -> list[str]:
    found = [
        f"{repo}: hook drifted from its template: {Path(h['copy']).name}"
        for h in cur.get("hooks", [])
        if h.get("status") == "drifted"
    ]
    if prev is not None:
        a, b = prev["always_loaded"]["tokens"], cur["always_loaded"]["tokens"]
        if a and (b - a) / a > TOKEN_GROWTH:
            found.append(f"{repo}: always-loaded tokens {a} -> {b} (+{round(100 * (b - a) / a)}%)")
    if last_verify is not None and last_verify.get("result") != "pass":
        found.append(
            f"{repo}: last verify run failed "
            f"({last_verify.get('commit')}, {str(last_verify.get('ts'))[:10]})"
        )
    return found


def _registered(runtime: Path) -> list[Path]:
    path = runtime / "target-repos.txt"
    lines = path.read_text().splitlines() if path.is_file() else []
    return [Path(ln.strip()) for ln in lines if ln.strip() and not ln.startswith("#")]


def _previous(audits: Path, today: str) -> dict[str, Any] | None:
    earlier = sorted(p for p in audits.glob("*.json") if p.stem < today)
    return json.loads(earlier[-1].read_text()) if earlier else None


def _last_verify(runtime: Path, repo: str) -> dict[str, Any] | None:
    rows: list[dict[str, Any]] = []
    for path in sorted((runtime / "telemetry" / repo).glob("verify-runs-*.jsonl")):
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return max(rows, key=lambda r: str(r.get("ts")), default=None)


def run(
    runtime: Path,
    update_log: str,
    update_rc: int,
    today: str,
    days: int = 7,
    audit_fn: Callable[[Path], dict[str, Any]] | None = None,
) -> tuple[str, list[str]]:
    audit_fn = audit_fn or (lambda r: repo_audit.audit(r, Path.home(), HARNESS / "templates/hooks"))
    found = update_regressions(update_log, update_rc)
    for repo in _registered(runtime):
        if not repo.is_dir():
            found.append(f"{repo.name}: registered but missing at {repo}")
            continue
        audits = runtime / "audits" / repo.name
        try:
            cur = audit_fn(repo)
        except Exception as e:  # noqa: BLE001 -- one broken repo must not hide the others
            found.append(f"{repo.name}: audit failed: {e}")
            continue
        prev = _previous(audits, today)
        audits.mkdir(parents=True, exist_ok=True)
        (audits / f"{today}.json").write_text(json.dumps(cur, indent=2) + "\n")
        found += repo_regressions(repo.name, prev, cur, _last_verify(runtime, repo.name))
    table = repo_trend.render(
        runtime / "audits", runtime, days, today=datetime.date.fromisoformat(today)
    )
    lines = [f"# Harness weekly {today}", "", "## Regressions", ""]
    lines += [f"- {f}" for f in found] or ["No regressions."]
    lines += ["", "## Target repos", "", table, ""]
    return "\n".join(lines), found


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--update-log", type=Path, required=True)
    ap.add_argument("--update-rc", type=int, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--runtime", type=Path, default=None)
    ap.add_argument("--today", default=None)
    args = ap.parse_args(argv)
    runtime = args.runtime or repo_trend._runtime_dir()
    today = args.today or datetime.datetime.now().astimezone().date().isoformat()
    try:
        log = args.update_log.read_text(encoding="utf-8", errors="replace")
        report, found = run(runtime, log, args.update_rc, today, days=args.days)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report, encoding="utf-8")
    except Exception as e:  # noqa: BLE001 -- exit 2 says no verdict, never a silent pass
        print(f"harness_weekly.py: no verdict: {e}", file=sys.stderr)
        return 2
    for f in found:
        print(f)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
