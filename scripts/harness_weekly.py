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
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

import repo_audit
import repo_trend

HARNESS = Path(__file__).resolve().parent.parent
TOKEN_GROWTH = 0.10
# Changes the global rules want an outside review for: hooks and gates, the shipped
# rules, install scripts, agent settings, CI, migrations.
RISKY_RE = re.compile(
    r"^(\.claude/hooks/|\.claude/settings|\.agents/|\.codex/|templates/hooks/|harness/guards/"
    r"|\.github/workflows/|agents/engineering-rules\.md$|agent-harness\.json$"
    r"|scripts/(install|uninstall|update|_lib|setup-[^/]*)\.sh$|scripts/_settings_merge\.py$"
    r"|scripts/harness_adapter\.py$)|(^|/)migrations/"
)
BOT_RE = re.compile(r"\[bot\]$|^renovate", re.IGNORECASE)
# A review counts for a commit when it ran in the same repo within this window
# after it: the rules ask for one review per branch before finishing, not per commit.
REVIEW_WINDOW = datetime.timedelta(days=2)


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


def _parse_ts(value: str) -> datetime.datetime:
    # macOS system Python 3.9: fromisoformat reads no "Z" and datetime.UTC is 3.11+
    ts = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))  # noqa: FURB162
    return ts if ts.tzinfo else ts.replace(tzinfo=datetime.timezone.utc)  # noqa: UP017


def review_coverage(
    repo: Path, runs: list[dict[str, Any]], since: datetime.datetime
) -> dict[str, Any]:
    """Risky commits since `since`, and how many an outside-agent review followed."""
    out = subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "log",
            f"--since={since.isoformat()}",
            "--name-only",
            "--format=%x1e%h%x1f%cI%x1f%an%x1f%s",
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    me = repo.resolve()
    reviews = []
    for r in runs:
        try:
            same = Path(str(r.get("repo"))).resolve() == me
            if r.get("purpose") == "review" and r.get("exit_code") == 0 and same:
                reviews.append(_parse_ts(str(r["timestamp"])))
        except (KeyError, ValueError):
            continue
    risky = reviewed = 0
    unreviewed: list[str] = []
    for rec in out.split("\x1e")[1:]:
        head, _, files = rec.partition("\n")
        sha, when, author, subject = head.split("\x1f", 3)
        if BOT_RE.search(author) or not any(RISKY_RE.search(f) for f in files.split()):
            continue
        risky += 1
        t = _parse_ts(when)
        if any(t <= r <= t + REVIEW_WINDOW for r in reviews):
            reviewed += 1
        else:
            unreviewed.append(f"{sha} {subject}")
    return {"risky": risky, "reviewed": reviewed, "unreviewed": unreviewed}


def _review_section(repos: list[Path], runtime: Path, since: datetime.datetime) -> list[str]:
    runs: list[dict[str, Any]] = []
    log = runtime / "state/outside-agent-runs.jsonl"
    for line in log.read_text().splitlines() if log.is_file() else []:
        try:
            runs.append(json.loads(line))
        except ValueError:
            continue
    rows = []
    for repo in repos:
        try:
            c = review_coverage(repo, runs, since)
        except (OSError, subprocess.CalledProcessError):
            continue
        latest = "; ".join(c["unreviewed"][:5]) or "-"
        rows.append(f"| {repo.name} | {c['risky']} | {c['reviewed']} | {latest} |")
    return [
        "## Outside reviews of risky commits",
        "",
        "Measured, not enforced. Only outside-agent reviews are logged; a subagent",
        "review leaves no record. Renovate's commits are left out.",
        "",
        "| repo | risky commits | with an outside review | unreviewed (latest 5) |",
        "|---|---|---|---|",
        *rows,
        "",
    ]


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
    extra_repos: tuple[Path, ...] = (HARNESS,),
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
    since = _parse_ts(f"{today}T00:00:00") - datetime.timedelta(days=days)
    repos = [r for r in [*_registered(runtime), *extra_repos] if r.is_dir()]
    lines += _review_section(repos, runtime, since)
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
