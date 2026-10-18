#!/usr/bin/env python3
"""Read and check a target repo's agent-harness.json.

The file is for the harness, not the agent (the agent reads AGENTS.md). It says
which harness commit the repo was synced to, its state files, its verify
commands, and its hooks in wiring order: each a shared template under
templates/hooks/<stack>/ or a repo-local file, run on `edit`, `stop` or `start` (session start).

Usage: harness_adapter.py check <repo> [--templates DIR] [--runtime DIR]
       harness_adapter.py drift <repo> [--templates DIR] [--file PATH]
       harness_adapter.py sync <repo> | register <repo> | sync-all
check exits 0 when the file is valid, 2 with one line per problem otherwise; the
version is reported against <runtime>/harness-version.json and never fails.
drift exits 2 when a listed template hook (.claude/hooks/<name>) differs from
its template outside the repo config block, the only part a repo may edit.
sync copies the listed template hooks (keeping each copy's config block) and
agent-hook.sh into .claude/hooks, writes the hook wiring for claude, codex and agy,
and sets harness.version to the installed commit. It never commits. register adds
a repo to <runtime>/target-repos.txt; sync-all (run by update.sh) syncs each one.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from repo_audit import CONFIG_END_RE, CONFIG_START, _strip_config

HARNESS = Path(__file__).resolve().parent.parent
FILENAME = "agent-harness.json"
SCHEMA_VERSION = 1
EVENTS = ("edit", "stop", "start")  # start: Claude SessionStart only
WRAPPER = "common/agent-hook.sh"
REGISTRY = "target-repos.txt"
EDIT_MATCHERS = {
    "claude": "Edit|Write|MultiEdit",
    "codex": "apply_patch|file_edit|Edit|Write|MultiEdit",
    "agy": "replace_file_content|write_to_file",
}
KEYS = {
    "schema_version": int,
    "harness": dict,
    "project": dict,
    "state_files": list,
    "verify": list,
    "hooks": list,
}


class AdapterError(Exception):
    pass


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
    if (repo / ".claude/hooks" / Path(WRAPPER).name).is_file():
        hooks = [*hooks, {"template": WRAPPER}]
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


def _config_block(text: str) -> str | None:
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.startswith(CONFIG_START):
            for j in range(i + 1, len(lines)):
                if CONFIG_END_RE.match(lines[j].rstrip("\n")):
                    return "".join(lines[i : j + 1])
            return None
    return None


def _merged(template: str, copy: str | None) -> str:
    """The template, with the copy's repo config block when both have one."""
    ours, theirs = _config_block(template), _config_block(copy) if copy else None
    return template.replace(ours, theirs, 1) if ours and theirs else template


def _write_if_changed(path: Path, text: str, changes: list[str], repo: Path) -> None:
    try:
        if path.read_text(encoding="utf-8") == text:
            return
    except OSError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    changes.append(str(path.relative_to(repo)))


def _group(commands: list[str], matcher: str | None = None) -> dict[str, Any]:
    g: dict[str, Any] = {} if matcher is None else {"matcher": matcher}
    g["hooks"] = [{"type": "command", "command": c} for c in commands]
    return g


def _wiring(hooks: list[dict[str, Any]]) -> dict[str, Any]:
    """Hook settings for each agent, from one list in wiring order."""
    paths = {
        ev: [
            f".claude/hooks/{Path(h['template']).name}" if "template" in h else h["local"]
            for h in hooks
            if h["event"] == ev
        ]
        for ev in EVENTS
    }

    def events(agent: str) -> dict[str, list[dict[str, Any]]]:
        def cmd(ev: str, p: str) -> str:
            return (
                f"bash {p}"
                if agent == "claude"
                else f"bash .claude/hooks/agent-hook.sh {agent} {ev} {p}"
            )

        out: dict[str, list[dict[str, Any]]] = {}
        if paths["edit"]:
            out["PostToolUse"] = [
                _group([cmd("edit", p) for p in paths["edit"]], EDIT_MATCHERS[agent])
            ]
        if paths["stop"]:
            out["Stop"] = [_group([cmd("stop", p) for p in paths["stop"]])]
        # codex and agy have no session-start event verified here; their AGENTS.md
        # startup step runs the same script instead.
        if paths["start"] and agent == "claude":
            out["SessionStart"] = [_group([cmd("start", p) for p in paths["start"]])]
        return out

    agy = events("agy")
    return {
        "claude": events("claude"),
        "codex": {"hooks": events("codex")},
        "agy": {
            name: {ev: agy[ev]}
            for name, ev in (("harness-edit", "PostToolUse"), ("harness-stop", "Stop"))
            if ev in agy
        },
    }


def _dump(data: Any) -> str:
    return json.dumps(data, indent=2) + "\n"


def sync(repo: Path, templates: Path, runtime: Path) -> list[str]:
    """Bring a target repo's hook copies and wiring up to the installed harness."""
    repo = repo.resolve()
    result = check(repo, templates=templates, runtime=runtime)
    if result.problems or result.data is None:
        raise AdapterError(f"{repo / FILENAME}: " + "; ".join(result.problems))
    data = result.data
    changes: list[str] = []
    hooks_dir = repo / ".claude/hooks"
    for rel in [h["template"] for h in data["hooks"] if "template" in h] + [WRAPPER]:
        copy = hooks_dir / Path(rel).name
        current = copy.read_text(encoding="utf-8") if copy.is_file() else None
        _write_if_changed(
            copy, _merged((templates / rel).read_text(encoding="utf-8"), current), changes, repo
        )

    wiring = _wiring(data["hooks"])
    settings = repo / ".claude/settings.json"
    try:
        claude = json.loads(settings.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        claude = {}
    if claude.get("hooks") != wiring["claude"]:
        claude["hooks"] = wiring["claude"]
        _write_if_changed(settings, _dump(claude), changes, repo)
    _write_if_changed(repo / ".codex/hooks.json", _dump(wiring["codex"]), changes, repo)
    _write_if_changed(repo / ".agents/hooks.json", _dump(wiring["agy"]), changes, repo)

    try:
        installed = json.loads((runtime / "harness-version.json").read_text()).get("short")
    except (OSError, ValueError):
        installed = None
    if installed and data["harness"]["version"] != installed:
        data["harness"]["version"] = installed
        _write_if_changed(repo / FILENAME, _dump(data), changes, repo)
    return changes


def register(repo: Path, templates: Path, runtime: Path) -> None:
    result = check(repo, templates=templates, runtime=runtime)
    if result.problems:
        raise AdapterError(f"{repo / FILENAME}: " + "; ".join(result.problems))
    path = runtime / REGISTRY
    entries = path.read_text().splitlines() if path.is_file() else []
    if str(repo.resolve()) not in entries:
        runtime.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            f.write(f"{repo.resolve()}\n")


def sync_all(templates: Path, runtime: Path) -> dict[str, str]:
    """Sync each registered repo: {path: 'missing' | 'up to date' | changes | error}."""
    path = runtime / REGISTRY
    report: dict[str, str] = {}
    for line in path.read_text().splitlines() if path.is_file() else []:
        entry = line.strip()
        if not entry or entry.startswith("#"):
            continue
        if not Path(entry).is_dir():
            report[entry] = "missing"
            continue
        try:
            changes = sync(Path(entry), templates=templates, runtime=runtime)
        except AdapterError as e:
            report[entry] = f"error: {e}"
            continue
        report[entry] = ", ".join(changes) if changes else "up to date"
    return report


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("command", choices=["check", "drift", "sync", "register", "sync-all"])
    ap.add_argument("repo", type=Path, nargs="?")
    ap.add_argument("--templates", type=Path, default=HARNESS / "templates/hooks")
    ap.add_argument("--runtime", type=Path, default=None)
    ap.add_argument("--file", type=Path, default=None)
    args = ap.parse_args(argv)
    runtime = args.runtime or _runtime_dir()
    if args.command == "sync-all":
        report = sync_all(templates=args.templates, runtime=runtime)
        for repo, status in report.items():
            print(f"  {repo}: {status}")
        if not report:
            print(f"  no target repos registered in {runtime / REGISTRY}")
        return 2 if any(s == "missing" or s.startswith("error") for s in report.values()) else 0
    if args.repo is None:
        ap.error(f"{args.command} needs a repo")
    if args.command in ("sync", "register"):
        try:
            if args.command == "register":
                register(args.repo, templates=args.templates, runtime=runtime)
                print(f"  registered {args.repo.resolve()}")
            else:
                changes = sync(args.repo, templates=args.templates, runtime=runtime)
                print(f"  {args.repo}: {', '.join(changes) if changes else 'up to date'}")
        except AdapterError as e:
            print(f"  FAIL  {e}")
            return 2
        return 0
    if args.command == "drift":
        found = drift(args.repo, templates=args.templates, only=args.file)
        for copy, tmpl in found:
            print(
                f"  DRIFT  {copy} differs from templates/hooks/{tmpl} outside its repo config block"
            )
        return 2 if found else 0
    result = check(args.repo, templates=args.templates, runtime=runtime)
    for p in result.problems:
        print(f"  FAIL  {p}")
    print(
        f"  {'OK  ' if not result.problems else 'FAIL'}  {args.repo / FILENAME}; harness version: {result.version_status}"
    )
    return 2 if result.problems else 0


if __name__ == "__main__":
    sys.exit(main())
