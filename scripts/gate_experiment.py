#!/usr/bin/env python3
"""Plant one defect at a time in a clone of the repo and record which gates catch it.

harness-verify.sh runs every gate even after one fails, so a single run per case shows the whole
picture: the gate the case was written for, and any other gate that also fails. A gate is only called
possibly redundant when every case it catches is also caught by another gate; a gate no valid case
exercises is "cannot judge", never "safe to remove". Nothing here edits or removes a gate.
See docs/stories/run-telemetry/gate-necessity.md.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import shutil
import string
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any

import _gate_names

ROOT = Path(__file__).resolve().parent.parent
CASES_FILE = ROOT / "tests" / "gate_cases" / "cases.json"
GATES = _gate_names.GATES
OPS = ("write", "append", "write_joined", "write_random", "json_append_feature")
BASELINE_ID = "baseline"
_RESULT = re.compile(r"^\s{2}(OK|FAIL|SKIP)\s+(.+?)\s+\(")


def _safe(work: Path, rel: str) -> Path:
    p = PurePosixPath(rel)
    if p.is_absolute() or ".." in p.parts or not rel:
        raise ValueError(f"path escapes the work tree: {rel!r}")
    out = (work / rel).resolve()
    if work.resolve() not in out.parents:
        raise ValueError(f"path escapes the work tree: {rel!r}")
    return out


def track(work: Path) -> None:
    """Stage planted files. Only for cases that need it: the type gate reads tracked files only,
    while the clean-state gate looks for files that are NOT committed, so staging would hide them."""
    subprocess.run(["git", "-C", str(work), "add", "-A"], check=True, capture_output=True)


def apply_ops(work: Path, ops: list[dict[str, Any]]) -> None:
    for op in ops:
        kind = op.get("op")
        if kind not in OPS:
            raise ValueError(f"unknown op: {kind!r}")
        target = _safe(work, str(op.get("path", "")))
        target.parent.mkdir(parents=True, exist_ok=True)
        if kind == "write":
            target.write_text(str(op["text"]), encoding="utf-8")
        elif kind == "write_joined":
            target.write_text("".join(str(x) for x in op["parts"]), encoding="utf-8")
        elif kind == "write_random":
            alphabet = string.ascii_letters + string.digits
            body = "".join(secrets.choice(alphabet) for _ in range(int(op["length"])))
            target.write_text(
                str(op["prefix"]) + str(op["infix"]) + body + str(op["suffix"]), encoding="utf-8"
            )
        elif kind == "append":
            with open(target, "a", encoding="utf-8") as f:
                f.write(str(op["text"]))
        else:
            data = json.loads(target.read_text(encoding="utf-8"))
            data.setdefault("features", []).append(op["feature"])
            target.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def parse_gate_results(output: str) -> dict[str, str]:
    results: dict[str, str] = {}
    for line in output.splitlines():
        m = _RESULT.match(line)
        if m:
            results[m.group(2).strip()] = m.group(1)
    return results


def _clone(src: Path, dst: Path) -> None:
    """A clone of the working tree, so uncommitted edits are tested too."""
    if dst.exists():
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "clone", "-q", str(src), str(dst)], check=True, capture_output=True)
    tracked = subprocess.run(
        ["git", "-C", str(src), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        check=True,
        capture_output=True,
    ).stdout.split(b"\0")
    for raw in tracked:
        if not raw:
            continue
        rel = raw.decode("utf-8", errors="surrogateescape")
        s, d = src / rel, dst / rel
        if s.is_file() and not s.is_symlink():
            d.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(s, d)
        elif not s.exists() and d.exists():
            d.unlink()
    staged = subprocess.run(
        ["git", "-C", str(src), "diff", "--cached", "--name-only", "-z"],
        check=True,
        capture_output=True,
    ).stdout.split(b"\0")
    for raw in staged:
        if raw and (dst / raw.decode("utf-8", errors="surrogateescape")).is_file():
            subprocess.run(
                ["git", "-C", str(dst), "add", "--", raw.decode("utf-8", errors="surrogateescape")],
                check=True,
                capture_output=True,
            )
    venv = src / ".venv"
    if venv.exists() and not (dst / ".venv").exists():
        (dst / ".venv").symlink_to(venv)
    pin = src / ".python-version"
    if pin.is_file() and not (dst / ".python-version").exists():
        shutil.copy(pin, dst / ".python-version")


def run_case(
    src: Path, case: dict[str, Any], work_root: Path, env: dict[str, str] | None = None
) -> dict[str, Any]:
    work = work_root / case["id"]
    _clone(src, work)
    apply_ops(work, case.get("ops", []))
    if case.get("stage"):
        track(work)
    runtime_dir = (env or {}).get("RUNTIME_DRIFT_GUARD_RUNTIME_DIR")
    if runtime_dir:
        _seed_runtime(src, Path(runtime_dir), work if case.get("seed_after_ops") else None)
    run_env = {**os.environ, **(env or {})}
    r = subprocess.run(
        ["bash", str(work / "scripts" / "harness-verify.sh")],
        cwd=work,
        env=run_env,
        capture_output=True,
        text=True,
        check=False,
        timeout=900,
    )
    results = parse_gate_results(r.stdout + r.stderr)
    return {
        "id": case["id"],
        "expect": case.get("expect"),
        "failed": [g for g, s in results.items() if s == "FAIL"],
        "exit": r.returncode,
    }


def analyze(rows: list[dict[str, Any]], baseline_failed: list[str] | None = None) -> dict[str, Any]:
    ignored = set(baseline_failed or [])
    cases = [r for r in rows if r["id"] != BASELINE_ID]
    broken = [r["id"] for r in cases if r["expect"] not in r["failed"]]
    valid = [
        {**r, "failed": [g for g in r["failed"] if g not in ignored]}
        for r in cases
        if r["id"] not in broken
    ]
    caught: dict[str, list[dict[str, Any]]] = {}
    for r in valid:
        for g in r["failed"]:
            caught.setdefault(g, []).append(r)
    verdict: dict[str, str] = {}
    for g in GATES:
        hits = caught.get(g, [])
        if g in ignored or not hits:
            verdict[g] = "cannot judge"
        elif all(len(c["failed"]) > 1 for c in hits):
            verdict[g] = "possibly redundant"
        else:
            verdict[g] = "needed"
    # A gate is only redundant if some other gate that stays could take over every case it catches.
    # Walk the candidates in order; once a gate is treated as removed, it cannot be the partner that
    # makes the next one look redundant.
    removed: set[str] = set()
    for g in GATES:
        if verdict[g] != "possibly redundant":
            continue
        if all(any(o not in removed and o != g for o in c["failed"]) for c in caught[g]):
            removed.add(g)
        else:
            verdict[g] = "needed if the gates it overlaps with are also removed"
    also = {r["id"]: [g for g in r["failed"] if g != r["expect"]] for r in valid}
    return {
        "broken": broken,
        "verdict": verdict,
        "also_caught_by": also,
        "baseline_failed": sorted(ignored),
    }


def render(rows: list[dict[str, Any]], result: dict[str, Any]) -> str:
    rows = [r for r in rows if r["id"] != BASELINE_ID]
    width = max([len(r["id"]) for r in rows] + [4])
    lines = [f"{'case'.ljust(width)}  {'expected'.ljust(14)}  caught by"]
    lines.append("-" * (width + 40))
    for r in rows:
        status = (
            "BROKEN (expected gate did not fail)"
            if r["id"] in result["broken"]
            else ", ".join(r["failed"])
        )
        lines.append(f"{r['id'].ljust(width)}  {str(r['expect']).ljust(14)}  {status or 'nothing'}")
    lines.append("")
    lines.append("gate verdicts (a verdict is evidence, not an instruction to remove anything):")
    for g in GATES:
        lines.append(f"  {g.ljust(14)} {result['verdict'][g]}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Plant defects in a clone and see which gates catch them."
    )
    ap.add_argument("--repo", type=Path, default=ROOT)
    ap.add_argument("--cases", type=Path, default=CASES_FILE)
    ap.add_argument(
        "--case", action="append", default=[], help="run only this case id (repeatable)"
    )
    ap.add_argument("--work-dir", type=Path, default=None)
    ap.add_argument("--json", action="store_true")
    ap.add_argument(
        "--no-baseline", action="store_true", help="skip the unmodified clone run (testing only)"
    )
    args = ap.parse_args(argv)
    cases = json.loads(args.cases.read_text(encoding="utf-8"))["cases"]
    known = {c["id"] for c in cases}
    unknown = [c for c in args.case if c not in known]
    if unknown:
        print(f"gate_experiment: unknown case id(s): {unknown}", file=sys.stderr)
        return 2
    chosen = [c for c in cases if not args.case or c["id"] in args.case]
    if not args.no_baseline:
        chosen = [{"id": BASELINE_ID, "expect": None, "ops": []}, *chosen]
    work_root = args.work_dir or Path(tempfile.mkdtemp(prefix="gate-exp-"))
    home = work_root / "_home"
    runtime = work_root / "_runtime"
    home.mkdir(parents=True, exist_ok=True)
    # The bare python3's pytest and lxml sit in the user site, which Python finds
    # through HOME; keep it while HOME is redirected.
    user_base = os.environ.get("PYTHONUSERBASE") or subprocess.run(
        ["python3", "-c", "import site; print(site.getuserbase())"],
        capture_output=True, text=True, check=False,
    ).stdout.strip()
    rows = []
    for case in chosen:
        runtime_case = runtime / case["id"]
        env = {"HOME": str(home), "RUNTIME_DRIFT_GUARD_RUNTIME_DIR": str(runtime_case)}
        if user_base:
            env["PYTHONUSERBASE"] = user_base
        row = run_case(args.repo, case, work_root, env=env)
        shutil.rmtree(work_root / case["id"], ignore_errors=True)
        rows.append(row)
        if case["id"] == BASELINE_ID and row["failed"]:
            print(
                f"gate_experiment: the unmodified baseline already fails {row['failed']}; "
                "fix that first, every result would be meaningless otherwise",
                file=sys.stderr,
            )
            return 2
    baseline: list[str] = next((r["failed"] for r in rows if r["id"] == BASELINE_ID), [])
    result = analyze(rows, baseline)
    print(json.dumps({"rows": rows, **result}, indent=2) if args.json else render(rows, result))
    return 0


def _seed_runtime(repo: Path, dst: Path, planted: Path | None = None) -> None:
    """Copy the files the runtime-drift gate compares so a clean clone starts in sync.

    With `planted`, copy them from the clone after the defect was planted, for cases that edit a
    runtime-copied file for a reason other than drift; only the drift case should differ from it.
    """
    dst.mkdir(parents=True, exist_ok=True)
    root = planted if planted is not None else repo
    for src, name in _gate_names.RUNTIME_FILES:
        s = root / src
        if s.is_file():
            (dst / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(s, dst / name)


if __name__ == "__main__":
    sys.exit(main())
