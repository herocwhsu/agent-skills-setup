#!/usr/bin/env python3
"""Run the fixed telemetry benchmark and compare harness versions.

Each task is a frozen prompt plus a fixture copied into a fresh git repo. A task passes only when every
scripted check passes; no model scores anything. Results embed the run_telemetry record of the session.
See docs/stories/run-telemetry/benchmark.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import run_telemetry
import state_layer_check
import trace_evaluation

ROOT = Path(__file__).resolve().parent.parent
BENCH = ROOT / "benchmarks" / "telemetry"
MIN_RUNS = 5
IGNORE = shutil.ignore_patterns("__pycache__", ".pytest_cache", "*.pyc", ".git")


def load_suite(bench: Path = BENCH) -> dict[str, Any]:
    data = json.loads((bench / "suite.json").read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("tasks"), list):
        raise ValueError("suite.json must be an object with a tasks list")
    return data


def suite_hash(bench: Path = BENCH) -> str:
    h = hashlib.sha256()
    paths = [bench / "suite.json"]
    for sub in ("fixtures", "hidden"):
        paths.extend(
            p
            for p in sorted((bench / sub).rglob("*"))
            if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc"
        )
    for p in paths:
        h.update(str(p.relative_to(bench)).encode())
        h.update(p.read_bytes())
    return h.hexdigest()[:12]


def _git(cwd: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )


def harness_commit(root: Path = ROOT) -> str:
    head = _git(root, "rev-parse", "--short", "HEAD").stdout.strip() or "unknown"
    dirty = _git(
        root, "status", "--porcelain", "--", ".", ":(exclude)docs/telemetry/benchmark"
    ).stdout.strip()
    return f"{head}-dirty" if dirty else head


def restore_names(directory: Path) -> None:
    for p in sorted(directory.rglob("*.fixture")):
        p.replace(p.with_suffix(""))


def _src(path: Path) -> Path:
    stored = path.with_name(path.name + ".fixture")
    return stored if stored.is_file() else path


def prepare(task: dict[str, Any], workdir: Path, bench: Path = BENCH) -> None:
    shutil.copytree(
        bench / "fixtures" / task["fixture"], workdir, dirs_exist_ok=True, ignore=IGNORE
    )
    restore_names(workdir)
    _git(workdir, "init", "-q")
    _git(workdir, "add", "-A")
    _git(
        workdir,
        "-c",
        "user.name=bench",
        "-c",
        "user.email=bench@example.invalid",
        "commit",
        "-q",
        "-m",
        "base",
    )


def changed_files(workdir: Path) -> set[str]:
    out = _git(workdir, "status", "--porcelain", "--untracked-files=all").stdout
    return {line[3:].strip() for line in out.splitlines() if line.strip()}


def _sha(path: Path) -> str | None:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def _pytest(workdir: Path, *files: str) -> bool:
    env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
    try:
        r = subprocess.run(
            [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", *files],
            cwd=workdir,
            capture_output=True,
            text=True,
            timeout=120,
            env=env,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False
    return r.returncode == 0


_NEGATION = re.compile(
    r"\bno\s+(off[- ]by[- ]one|problems?|issues?|bugs?|defects?|errors?|portability)"
    r"|\bnot\s+(an?\s+)?(off[- ]by[- ]one|bug|issue|defect|problem)"
    r"|\b(works?|looks?|is|are|seems?)\s+(fine|correct|ok|okay|good)"
    r"|\b(has|have|had)\s+(full\s+|good\s+)?(test\s+)?coverage"
    r"|\b(is|are)\s+(fully\s+)?covered"
    r"|\bwithout (any )?(issues?|problems?)",
    re.I,
)


def _sentences(text: str) -> list[str]:
    return [p for p in re.split(r"(?<=[.!?])\s+|\n+", text) if p.strip()]


def _found(text: str, subject: str, evidence: str) -> bool:
    parts = _sentences(text)
    for i, sentence in enumerate(parts):
        if not re.search(evidence, sentence, re.I) or _NEGATION.search(sentence):
            continue
        around = " ".join(parts[max(0, i - 1) : i + 2])
        if re.search(subject, around, re.I):
            return True
    return False


def score_review(text: str) -> dict[str, bool]:
    return {
        "found_logic_defect": _found(
            text,
            r"paginate",
            r"off[- ]by[- ]one|len\(items\)\s*-\s*1|last (item|element)|drops?|omits?|skips?|truncat",
        ),
        "found_test_gap": _found(
            text,
            r"\btests?\b|test_paginate",
            r"last page|partial|final page|boundary|edge case|not covered|no test|missing test|coverage|untested|never (test|exercis)",
        ),
        "found_portability_defect": _found(
            text,
            r"mapfile",
            r"bash ?3|3\.2|macos|portab|bsd|not available|unavailable|builtin|older bash|does not exist",
        ),
    }


def _feature_map(workdir: Path) -> dict[str, dict[str, Any]]:
    data = json.loads((workdir / "feature_list.json").read_text(encoding="utf-8"))
    feats = list(state_layer_check._feature_list(data))
    feats += state_layer_check._archived_features(data, workdir)
    return {f["id"]: f for f in feats if isinstance(f, dict) and isinstance(f.get("id"), str)}


def _feat900_done(workdir: Path) -> bool:
    data = json.loads((workdir / "feature_list.json").read_text(encoding="utf-8"))
    feats = list(state_layer_check._feature_list(data))
    feats += state_layer_check._archived_features(data, workdir)
    for f in feats:
        if isinstance(f, dict) and f.get("id") == "feat-900":
            return f.get("status") == "done" and state_layer_check.has_text(f.get("evidence"))
    return False


def score(
    task: dict[str, Any],
    workdir: Path,
    *,
    final_text: str,
    outside_rows: list[dict[str, Any]],
    bench: Path = BENCH,
) -> dict[str, bool]:
    tid = task["id"]
    fixture = bench / "fixtures" / task["fixture"]
    changed = changed_files(workdir)
    if tid == "B1":
        untouched = _sha(workdir / "test_stats.py") == _sha(_src(fixture / "test_stats.py"))
        only = changed == {"stats.py"}
        shutil.copy(_src(bench / "hidden/B1/test_stats.py"), workdir / "test_stats.py")
        return {
            "tests_untouched": untouched,
            "only_stats_changed": only,
            "hidden_tests_pass": _pytest(workdir, "test_stats.py"),
        }
    if tid == "B2":
        shutil.copy(_src(fixture / "test_greeter.py"), workdir / "test_original_greeter.py")
        shutil.copy(_src(bench / "hidden/B2/test_shout.py"), workdir / "test_shout.py")
        readme = (
            (workdir / "README.md").read_text(encoding="utf-8")
            if (workdir / "README.md").is_file()
            else ""
        )
        return {
            "original_tests_pass": _pytest(workdir, "test_original_greeter.py"),
            "hidden_tests_pass": _pytest(workdir, "test_shout.py"),
            "readme_documents_option": bool(
                re.search(r"--shout", readme) and re.search(r"shout\s*=", readme)
            ),
        }
    if tid == "B3":
        return {**score_review(final_text), "no_files_changed": not changed}
    if tid == "B4":
        return {
            "outside_run_independent": any(
                r.get("independent") is True and r.get("exit_code") == 0 for r in outside_rows
            ),
            "review_non_empty": bool(final_text.strip()),
            "no_files_changed": not changed,
        }
    if tid == "B5":
        try:
            state_layer_check.check(workdir / "feature_list.json", [])
            valid = True
            done = _feat900_done(workdir)
            final = _feature_map(workdir)
            original = _feature_map(fixture)
        except (state_layer_check.StateLayerError, OSError, ValueError, KeyError):
            valid, done, final, original = False, False, {}, {}
        kept = bool(original) and all(
            final.get(fid) == feat for fid, feat in original.items() if fid != "feat-900"
        )
        progress = workdir / "PROGRESS.md"
        return {
            "state_layer_valid": valid,
            "within_budget": not trace_evaluation.check_thresholds(workdir),
            "feat900_done_with_evidence": done,
            "no_features_lost": kept and "feat-900" in final,
            "progress_updated": progress.is_file()
            and "feat-900" in progress.read_text(encoding="utf-8")
            and _sha(progress) != _sha(fixture / "PROGRESS.md"),
        }
    raise ValueError(f"unknown task id: {tid}")


def outside_log_path() -> Path:
    base = os.environ.get("OUTSIDE_AGENT_DIR")
    root = Path(base) if base else Path.home() / ".agent-skills-setup"
    return root / "state" / "outside-agent-runs.jsonl"


def outside_rows_since(started: datetime, log: Path) -> list[dict[str, Any]]:
    if not log.is_file():
        return []
    rows = []
    for r in run_telemetry._read_rows(log)[0]:
        ts = r.get("timestamp")
        try:
            if isinstance(ts, str) and run_telemetry.parse_ts(ts) >= started:
                rows.append(r)
        except ValueError:
            continue
    return rows


def find_session(session_id: str) -> Path | None:
    for p in (Path.home() / ".claude" / "projects").glob(f"*/{session_id}.jsonl"):
        return p
    return None


def run_agent(
    task: dict[str, Any],
    workdir: Path,
    *,
    model: str | None,
    timeout: int,
    agent_cmd: list[str] | None,
    bench: Path = BENCH,
) -> dict[str, Any]:
    sid = str(uuid.uuid4())
    env = {k: v for k, v in os.environ.items() if k not in ("CLAUDECODE", "CLAUDE_CODE_SESSION_ID")}
    if agent_cmd:
        env.update({"BENCH_TASK_ID": task["id"], "BENCH_DIR": str(bench)})
    if agent_cmd:
        cmd = list(agent_cmd)
    else:
        cmd = [
            "claude",
            "-p",
            task["prompt"],
            "--session-id",
            sid,
            "--output-format",
            "json",
            "--permission-mode",
            "acceptEdits",
            "--allowedTools",
            ",".join(task["allowed_tools"]),
        ]
        if model:
            cmd += ["--model", model]
    t0 = datetime.now(UTC)
    launch_error = False
    try:
        r = subprocess.run(
            cmd, cwd=workdir, capture_output=True, text=True, timeout=timeout, env=env, check=False
        )
        code, out, timed_out = r.returncode, r.stdout, False
    except subprocess.TimeoutExpired:
        code, out, timed_out = -1, "", True
    except OSError:
        code, out, timed_out, launch_error = -1, "", False, True
    text = out
    try:
        parsed = json.loads(out)
        if isinstance(parsed, dict) and isinstance(parsed.get("result"), str):
            text = parsed["result"]
    except ValueError:
        pass
    return {
        "session_id": sid,
        "exit_code": code,
        "timed_out": timed_out,
        "launch_error": launch_error,
        "duration_ms": int((datetime.now(UTC) - t0).total_seconds() * 1000),
        "text": text,
    }


def run_one(
    task: dict[str, Any],
    *,
    model: str | None = None,
    timeout: int = 900,
    agent_cmd: list[str] | None = None,
    keep: bool = False,
    bench: Path = BENCH,
    root: Path = ROOT,
    outside_log: Path | None = None,
) -> dict[str, Any]:
    started = datetime.now(UTC)
    workdir = Path(tempfile.mkdtemp(prefix=f"bench-{task['id']}-"))
    try:
        prepare(task, workdir, bench)
        agent = run_agent(
            task, workdir, model=model, timeout=timeout, agent_cmd=agent_cmd, bench=bench
        )
        log = outside_log or outside_log_path()
        checks = score(
            task,
            workdir,
            final_text=agent["text"],
            outside_rows=outside_rows_since(started, log),
            bench=bench,
        )
    finally:
        if keep:
            print(f"kept {workdir}", file=sys.stderr)
        else:
            shutil.rmtree(workdir, ignore_errors=True)
    session = find_session(agent["session_id"])
    telemetry = (
        run_telemetry.collect_run(
            session, start=started.isoformat(), outside_log=outside_log or outside_log_path()
        )
        if session
        else None
    )
    models = telemetry["parent"]["models"] if telemetry else []
    passed = all(checks.values()) and not agent["timed_out"] and agent["exit_code"] == 0
    return {
        "schema_version": 1,
        "run_id": f"{task['id']}-{agent['session_id'][:8]}",
        "task_id": task["id"],
        "kind": task.get("kind"),
        "harness_commit": harness_commit(root),
        "suite_hash": suite_hash(bench),
        "model": models[0] if models else (model or "unknown"),
        "started": started.isoformat(),
        "passed": passed,
        "first_pass": passed,
        "checks": checks,
        "agent": {k: agent[k] for k in ("exit_code", "timed_out", "launch_error", "duration_ms")},
        "human_interventions": run_telemetry.metric(
            0,
            "headless run",
            note="claude -p takes no further input, so none is possible by construction",
        ),
        "gate_failures": run_telemetry.missing("fixture repos have no harness gates"),
        "telemetry": telemetry,
    }


def _metric_value(m: Any) -> int | float | None:
    if isinstance(m, dict) and m.get("status") != "missing":
        v = m.get("value")
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            return v
    return None


def run_numbers(run: dict[str, Any]) -> dict[str, float | None]:
    t = run.get("telemetry")
    if not isinstance(t, dict):
        return {"parent_out": None, "sub_out": None, "wall_ms": None}
    parent = _metric_value(t.get("parent", {}).get("tokens", {}).get("output_tokens_sum"))
    subs = t.get("subagents")
    sub_out: float | None = None
    if isinstance(subs, list) and all(isinstance(s, dict) for s in subs):
        sub_vals = [_metric_value(s.get("tokens", {}).get("output_tokens_sum")) for s in subs]
        if all(v is not None for v in sub_vals):
            sub_out = float(sum(v for v in sub_vals if v is not None))
    return {
        "parent_out": None if parent is None else float(parent),
        "sub_out": sub_out,
        "wall_ms": None
        if _metric_value(t.get("wall_time_ms")) is None
        else float(_metric_value(t["wall_time_ms"]) or 0),
    }


def _summary(values: list[float | None]) -> dict[str, float] | None:
    if not values or any(v is None for v in values):
        return None
    nums = [v for v in values if v is not None]
    return {"median": statistics.median(nums), "min": min(nums), "max": max(nums)}


def group_runs(runs: list[dict[str, Any]]) -> dict[tuple[str, str, str, str], list[dict[str, Any]]]:
    groups: dict[tuple[str, str, str, str], list[dict[str, Any]]] = {}
    for r in runs:
        if isinstance(r.get("agent"), dict) and r["agent"].get("launch_error") is True:
            continue
        key = (
            str(r.get("task_id")),
            str(r.get("harness_commit")),
            str(r.get("model")),
            str(r.get("suite_hash")),
        )
        groups.setdefault(key, []).append(r)
    return groups


def summarize_group(runs: list[dict[str, Any]]) -> dict[str, Any]:
    nums = [run_numbers(r) for r in runs]
    return {
        "runs": len(runs),
        "first_pass_rate": _summary([1.0 if r.get("first_pass") is True else 0.0 for r in runs]),
        "parent_out": _summary([n["parent_out"] for n in nums]),
        "sub_out": _summary([n["sub_out"] for n in nums]),
        "wall_ms": _summary([n["wall_ms"] for n in nums]),
    }


def verdict(a: dict[str, Any], b: dict[str, Any], metric: str) -> str:
    if a["runs"] < MIN_RUNS or b["runs"] < MIN_RUNS:
        return "insufficient runs"
    sa, sb = a[metric], b[metric]
    if sa is None or sb is None:
        return "n/a"
    lo_a, hi_a, lo_b, hi_b = sa["min"], sa["max"], sb["min"], sb["max"]
    if hi_a < lo_b:
        return "B higher"
    if hi_b < lo_a:
        return "B lower"
    return "no real difference"


def load_results(directory: Path) -> list[dict[str, Any]]:
    out = []
    for p in sorted(directory.glob("*.json")):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError, RecursionError):
            continue
        if isinstance(d, dict) and "task_id" in d and "checks" in d:
            out.append(d)
    return out


def compare(runs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_task: dict[str, list[tuple[tuple[str, str, str, str], dict[str, Any]]]] = {}
    for key, rs in group_runs(runs).items():
        by_task.setdefault(key[0], []).append((key, summarize_group(rs)))
    rows = []
    for task, groups in sorted(by_task.items()):
        groups.sort(key=lambda g: g[0][1])
        for i, (ka, sa) in enumerate(groups):
            for kb, sb in groups[i + 1 :]:
                if ka[2] != kb[2] or ka[3] != kb[3]:
                    continue
                rows.append(
                    {
                        "task": task,
                        "a": ka[1],
                        "b": kb[1],
                        "model": ka[2],
                        "runs": f"{sa['runs']} vs {sb['runs']}",
                        **{
                            m: verdict(sa, sb, m)
                            for m in ("first_pass_rate", "parent_out", "sub_out", "wall_ms")
                        },
                    }
                )
    return rows


def _run_cmd(args: argparse.Namespace) -> int:
    suite = load_suite()
    runtime_script = Path.home() / ".agent-skills-setup" / "outside-agent.sh"
    wanted = set(args.task) if args.task else {t["id"] for t in suite["tasks"]}
    unknown = wanted - {t["id"] for t in suite["tasks"]}
    if unknown:
        print(f"telemetry_benchmark: unknown task id(s): {sorted(unknown)}", file=sys.stderr)
        return 2
    args.out_dir.mkdir(parents=True, exist_ok=True)
    failures = 0
    for task in suite["tasks"]:
        if task["id"] not in wanted:
            continue
        if "outside_agent" in task.get("requires", []) and not runtime_script.is_file():
            print(f"{task['id']}: SKIPPED, outside-agent.sh is not installed", file=sys.stderr)
            continue
        for n in range(args.runs):
            rec = run_one(task, model=args.model, timeout=args.timeout, keep=args.keep)
            path = args.out_dir / f"{rec['run_id']}.json"
            path.write_text(json.dumps(rec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            status = (
                "PASS"
                if rec["passed"]
                else "FAIL " + ",".join(k for k, v in rec["checks"].items() if not v)
            )
            print(f"{task['id']} run {n + 1}/{args.runs}: {status} -> {path}")
            failures += 0 if rec["passed"] else 1
    return 1 if failures else 0


def _compare_cmd(args: argparse.Namespace) -> int:
    runs = load_results(args.dir)
    if not runs:
        print(f"telemetry_benchmark: no results in {args.dir}", file=sys.stderr)
        return 2
    rows = compare(runs)
    if not rows:
        print("only one harness version per task and model so far; nothing to compare")
        return 0
    cols = [
        "task",
        "a",
        "b",
        "model",
        "runs",
        "first_pass_rate",
        "parent_out",
        "sub_out",
        "wall_ms",
    ]
    widths = {c: max(len(c), *(len(str(r[c])) for r in rows)) for c in cols}
    print("  ".join(c.ljust(widths[c]) for c in cols))
    for r in rows:
        print("  ".join(str(r[c]).ljust(widths[c]) for c in cols))
    print(
        f"\nA verdict needs at least {MIN_RUNS} runs per version and non-overlapping min-max ranges; n/a = a run had a missing metric."
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Fixed-task harness benchmark.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="run tasks and write one result per run")
    r.add_argument("--task", action="append", help="task id (repeatable); default all")
    r.add_argument("--runs", type=int, default=1)
    r.add_argument("--model")
    r.add_argument("--timeout", type=int, default=900)
    r.add_argument("--keep", action="store_true", help="keep the work directory")
    r.add_argument("--out-dir", type=Path, default=Path("docs/telemetry/benchmark"))
    c = sub.add_parser("compare", help="compare harness versions from saved results")
    c.add_argument("--dir", type=Path, default=Path("docs/telemetry/benchmark"))
    args = ap.parse_args(argv)
    return _run_cmd(args) if args.cmd == "run" else _compare_cmd(args)


if __name__ == "__main__":
    sys.exit(main())
