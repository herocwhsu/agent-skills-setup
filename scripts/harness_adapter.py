#!/usr/bin/env python3
"""Read and check a target repo's agent-harness.json.

The file is for the harness, not the agent (the agent reads AGENTS.md). It says
which harness commit the repo was synced to, its state files, its verify
commands, and its hooks in wiring order: each a shared template under
templates/hooks/<stack>/ or a repo-local file, run on `edit` or `stop`.

Usage: harness_adapter.py check <repo> [--templates DIR] [--runtime DIR]
       harness_adapter.py drift <repo> [--templates DIR] [--file PATH]
check exits 0 when the file is valid, 2 with one line per problem otherwise; the
version is reported against <runtime>/harness-version.json and never fails.
drift exits 2 when a listed template hook (.claude/hooks/<name>) differs from
its template outside the repo config block, the only part a repo may edit.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from repo_audit import _strip_config

HARNESS = Path(__file__).resolve().parent.parent
FILENAME = "agent-harness.json"
SCHEMA_VERSION = 1
EVENTS = ("edit", "stop")
KEYS = {
    "schema_version": int,
    "harness": dict,
    "project": dict,
    "state_files": list,
    "verify": list,
    "hooks": list,
}


@dataclass
class Result:
    data: dict[str, Any] | None = None
    problems: list[str] = field(default_factory=list)
    version_status: str = "unknown"


def _runtime_dir() -> Path:
    marker = HARNESS / ".skills-repo-id"
    name = marker.read_text().split()[0] if marker.is_file() else "agent-skills-setup"
    return Path.home() / f".{name}"


def _inside(base: Path, rel: str) -> Path | None:
    path = (base / rel).resolve()
    return path if path.is_relative_to(base.resolve()) else None


def _check_hooks(hooks: list[Any], repo: Path, templates: Path, problems: list[str]) -> None:
    for i, h in enumerate(hooks):
        where = f"hooks[{i}]"
        if not isinstance(h, dict) or set(h) - {"template", "local", "event"}:
            problems.append(f"{where}: must be an object with template or local, and event")
            continue
        if ("template" in h) == ("local" in h):
            problems.append(f"{where}: needs exactly one of template or local")
            continue
        if h.get("event") not in EVENTS:
            problems.append(
                f"{where}: event must be one of {', '.join(EVENTS)}, got {h.get('event')!r}"
            )
        kind = "template" if "template" in h else "local"
        base = templates if kind == "template" else repo
        rel = h[kind]
        target = _inside(base, rel) if isinstance(rel, str) else None
        if target is None or not target.is_file():
            problems.append(f"{where}: {kind} {rel!r} is not a file under {base}")


def _version_status(data: dict[str, Any], runtime: Path) -> str:
    try:
        installed = json.loads((runtime / "harness-version.json").read_text())
    except (OSError, ValueError):
        return "unknown"
    ours = str(data.get("harness", {}).get("version", ""))
    commit = str(installed.get("commit") or "")
    short = str(installed.get("short") or commit[:7])
    if ours and commit and (commit.startswith(ours) or ours == installed.get("describe")):
        return "in sync"
    return f"differs: repo synced at {ours or '?'}, installed {short or '?'}"


def check(repo: Path, templates: Path, runtime: Path) -> Result:
    path = repo / FILENAME
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return Result(problems=[f"no {FILENAME} in {repo}"])
    except (OSError, ValueError) as e:
        return Result(problems=[f"{path} is not valid JSON: {e}"])
    if not isinstance(data, dict):
        return Result(problems=[f"{path}: top level must be an object"])

    problems: list[str] = []
    problems += [f"unknown key {k!r}" for k in data if k not in KEYS]
    for key, typ in KEYS.items():
        if key not in data:
            problems.append(f"missing key {key!r}")
        elif not isinstance(data[key], typ) or isinstance(data[key], bool):
            problems.append(f"{key} must be {typ.__name__}")
    if data.get("schema_version") != SCHEMA_VERSION:
        problems.append(f"schema_version must be {SCHEMA_VERSION}")
    h = data.get("harness")
    if not (
        isinstance(h, dict)
        and isinstance(h.get("source"), str)
        and isinstance(h.get("version"), str)
    ):
        problems.append("harness must have string source and version")
    if not (isinstance(data.get("project"), dict) and isinstance(data["project"].get("name"), str)):
        problems.append("project must have a string name")
    verify = data.get("verify")
    if isinstance(verify, list) and (
        not verify or not all(isinstance(c, str) and c for c in verify)
    ):
        problems.append("verify must list at least one command")
    for f in data.get("state_files") or []:
        target = _inside(repo, f) if isinstance(f, str) else None
        if target is None or not target.is_file():
            problems.append(f"state file {f!r} does not exist")
    if isinstance(data.get("hooks"), list):
        _check_hooks(data["hooks"], repo, templates, problems)

    return Result(data=data, problems=problems, version_status=_version_status(data, runtime))


def drift(repo: Path, templates: Path, only: Path | None = None) -> list[tuple[str, str]]:
    """(copy, template) for each listed template hook that differs from its template."""
    try:
        hooks = json.loads((repo / FILENAME).read_text(encoding="utf-8")).get("hooks", [])
    except (OSError, ValueError, AttributeError):
        return []
    out: list[tuple[str, str]] = []
    for h in hooks:
        rel = h.get("template") if isinstance(h, dict) else None
        if not isinstance(rel, str):
            continue
        copy = repo / ".claude/hooks" / Path(rel).name
        if only is not None and copy.resolve() != only.resolve():
            continue
        try:
            same = _strip_config(copy.read_text()) == _strip_config((templates / rel).read_text())
        except OSError:
            same = False
        if not same:
            out.append((str(copy.relative_to(repo)), rel))
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("command", choices=["check", "drift"])
    ap.add_argument("repo", type=Path)
    ap.add_argument("--templates", type=Path, default=HARNESS / "templates/hooks")
    ap.add_argument("--runtime", type=Path, default=None)
    ap.add_argument("--file", type=Path, default=None)
    args = ap.parse_args(argv)
    if args.command == "drift":
        found = drift(args.repo, templates=args.templates, only=args.file)
        for copy, tmpl in found:
            print(
                f"  DRIFT  {copy} differs from templates/hooks/{tmpl} outside its repo config block"
            )
        return 2 if found else 0
    result = check(args.repo, templates=args.templates, runtime=args.runtime or _runtime_dir())
    for p in result.problems:
        print(f"  FAIL  {p}")
    print(
        f"  {'OK  ' if not result.problems else 'FAIL'}  {args.repo / FILENAME}; harness version: {result.version_status}"
    )
    return 2 if result.problems else 0


if __name__ == "__main__":
    sys.exit(main())
