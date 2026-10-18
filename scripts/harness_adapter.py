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
global-wiring --agent <claude|codex|gemini> [--hooks-dir DIR] prints the user-level
hook settings that run <runtime>/hooks/global-hook.sh, for install.sh to merge.
store-packs --agent A --skills-dir DIR moves the skills of every pack but core from
an agent's global skills dir to <runtime>/pack-skills/A; sync links the packs a
repo lists into its .claude/skills, .agents/skills and .kiro/skills (sync-all also
into the repos' shared parent folder); unlink-packs --agent A undoes it for uninstall.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from repo_audit import CONFIG_END_RE, CONFIG_START, _strip_config, load_packs

HARNESS = Path(__file__).resolve().parent.parent
FILENAME = "agent-harness.json"
SCHEMA_VERSION = 1
EVENTS = ("edit", "stop", "start")  # start: Claude SessionStart only
WRAPPER = "common/agent-hook.sh"
REGISTRY = "target-repos.txt"
PACK_STORE = "pack-skills"
# Where each agent reads a repo's skills (feat-083), and whose stored copy to link.
REPO_SKILL_DIRS = {
    ".claude/skills": ("claude",),
    ".agents/skills": ("gemini", "codex"),
    ".kiro/skills": ("kiro",),
}
EXCLUDE_BEGIN = "# BEGIN agent-skills-setup pack skills (harness_adapter.py sync)"
EXCLUDE_END = "# END agent-skills-setup pack skills"
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
        if not isinstance(h, dict) or set(h) - {"template", "local", "event", "timeout"}:
            problems.append(
                f"{where}: must be an object with template or local, event, optional timeout"
            )
            continue
        if "timeout" in h and not (
            isinstance(h["timeout"], int)
            and not isinstance(h["timeout"], bool)
            and h["timeout"] > 0
        ):
            problems.append(f"{where}: timeout must be a positive number of seconds")
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
    # sync bumps the version only with a real change, so a newer install is normal
    # here; whether anything is out of date is drift's call.
    return f"last changed by {ours or '?'}, installed {short or '?'}"


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
    problems += [f"unknown key {k!r}" for k in data if k not in KEYS and k != "skill_packs"]
    if "skill_packs" in data:
        known = set(load_packs()) - {"core"}
        sp = data["skill_packs"]
        if not isinstance(sp, list) or not all(isinstance(p, str) and p in known for p in sp):
            problems.append(
                f"skill_packs must list packs from config/skill-packs.json: {sorted(known)}"
            )
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


def _group(commands: list[tuple[str, int | None]], matcher: str | None = None) -> dict[str, Any]:
    g: dict[str, Any] = {} if matcher is None else {"matcher": matcher}
    g["hooks"] = [
        {"type": "command", "command": c, **({"timeout": s} if s else {})} for c, s in commands
    ]
    return g


def _wiring(hooks: list[dict[str, Any]]) -> dict[str, Any]:
    """Hook settings for each agent, from one list in wiring order."""
    paths = {
        ev: [
            (
                f".claude/hooks/{Path(h['template']).name}" if "template" in h else h["local"],
                h.get("timeout"),
            )
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
                # agy runs a hook from the folder holding hooks.json, not the repo root.
                else f'cd "$(git rev-parse --show-toplevel)" && '
                f"bash .claude/hooks/agent-hook.sh {agent} {ev} {p}"
            )

        out: dict[str, list[dict[str, Any]]] = {}
        if paths["edit"]:
            out["PostToolUse"] = [
                _group([(cmd("edit", p), s) for p, s in paths["edit"]], EDIT_MATCHERS[agent])
            ]
        if paths["stop"]:
            stop = _group([(cmd("stop", p), s) for p, s in paths["stop"]])
            # agy takes a matcher group only on tool events; it rejects the whole
            # file when a Stop entry is a group instead of a hook.
            out["Stop"] = stop["hooks"] if agent == "agy" else [stop]
        # codex and agy have no session-start event verified here; their AGENTS.md
        # startup step runs the same script instead.
        if paths["start"] and agent == "claude":
            out["SessionStart"] = [_group([(cmd("start", p), s) for p, s in paths["start"]])]
        return out

    agy = events("agy")
    return {
        "claude": events("claude"),
        "codex": {"hooks": events("codex")},
        "agy": {
            name: {ev: agy[ev]}
            for name, ev in zip(AGY_GROUPS, ("PostToolUse", "Stop"))
            if ev in agy
        },
    }


def pack_skill_names(packs: dict[str, list[str]] | None = None) -> set[str]:
    """Skills that belong to a pack other than core: global only through a repo."""
    packs = load_packs() if packs is None else packs
    return {s for name, skills in packs.items() if name != "core" for s in skills}


def store_pack_skills(
    skills_dir: Path,
    store: Path,
    names: set[str],
    installed: set[str] | None = None,
    repo_dir: Path | None = None,
) -> list[str]:
    """Move pack skills out of an agent's global skills dir into the pack store.

    install.sh installs every skill globally, then calls this, so a pack skill is
    loaded only in the repos whose agent-harness.json lists its pack. A link moves
    as a link; a copied skill dir replaces the stored one. Pack names are generic
    (review, testing), so with `installed` only names this install put there move,
    and with `repo_dir` a link moves only when it points into its skills/.
    """
    moved: list[str] = []
    for name in sorted(names):
        src = skills_dir / name
        if not (src.is_symlink() or src.exists()):
            continue
        if installed is not None and name not in installed:
            continue
        if repo_dir is not None and src.is_symlink():
            target = Path(os.readlink(src))
            if not target.is_absolute() or not target.is_relative_to(repo_dir / "skills"):
                continue
        dst = store / name
        store.mkdir(parents=True, exist_ok=True)
        if dst.is_symlink() or dst.is_file():
            dst.unlink()
        elif dst.exists():
            shutil.rmtree(dst)
        if src.is_symlink():
            dst.symlink_to(os.readlink(src))
            src.unlink()
        else:
            shutil.move(str(src), str(dst))
        moved.append(name)
    return moved


def _link_pack_skills(repo: Path, data: dict[str, Any], runtime: Path, changes: list[str]) -> None:
    store = runtime / PACK_STORE
    packs = load_packs()
    wanted = sorted({s for p in data.get("skill_packs", []) for s in packs.get(p, [])})
    every = tuple(a for agents in REPO_SKILL_DIRS.values() for a in agents)
    linked: list[str] = []
    for rel, agents in REPO_SKILL_DIRS.items():
        d = repo / rel
        if d.is_dir():
            for p in sorted(d.iterdir()):
                if (
                    p.is_symlink()
                    and Path(os.readlink(p)).is_relative_to(store)
                    and p.name not in wanted
                ):
                    p.unlink()
                    changes.append(f"{rel}/{p.name} (unlinked)")
        order = agents + tuple(a for a in every if a not in agents)
        for name in wanted:
            src = next((store / a / name for a in order if (store / a / name).exists()), None)
            link = d / name
            own = (link.exists() or link.is_symlink()) and not (
                link.is_symlink() and Path(os.readlink(link)).is_relative_to(store)
            )
            if src is None or own:
                continue  # not installed on this host, or the repo's own skill wins
            linked.append(f"{rel}/{name}")
            if link.is_symlink() and os.readlink(link) == str(src):
                continue
            d.mkdir(parents=True, exist_ok=True)
            if link.is_symlink():
                link.unlink()
            link.symlink_to(src)
            changes.append(f"{rel}/{name}")
    _write_exclude(repo, linked, changes)


def _write_exclude(repo: Path, paths: list[str], changes: list[str]) -> None:
    """Keep the host-specific links out of git, in a block of .git/info/exclude."""
    try:
        rel = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--git-path", "info/exclude"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return
    path = Path(rel) if Path(rel).is_absolute() else repo / rel
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    lines = text.splitlines()
    if EXCLUDE_BEGIN in lines:
        i = lines.index(EXCLUDE_BEGIN)
        j = lines.index(EXCLUDE_END, i) if EXCLUDE_END in lines[i:] else len(lines) - 1
        lines = lines[:i] + lines[j + 1 :]
    if paths:
        lines += [EXCLUDE_BEGIN] + [f"/{p}" for p in sorted(paths)] + [EXCLUDE_END]
    new = "\n".join(lines) + "\n" if lines else ""
    if new != text:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(new, encoding="utf-8")
        changes.append("info/exclude")


GLOBAL_STOP_TIMEOUT = 120


def global_wiring(agent: str, hooks_dir: Path) -> dict[str, Any]:
    """User-level settings that run <hooks_dir>/global-hook.sh, in the agent's own shape.

    agent is install.sh's name for it: claude, codex or gemini (agy).
    """
    name = {"claude": "claude", "codex": "codex", "gemini": "agy"}.get(agent)
    if name is None:
        raise AdapterError(f"no global hooks for agent '{agent}'")

    def cmd(ev: str) -> str:
        return f'bash "{hooks_dir}/global-hook.sh" {name} {ev}'

    stop = _group([(cmd("stop"), GLOBAL_STOP_TIMEOUT)])
    out: dict[str, Any] = {
        "PostToolUse": [_group([(cmd("edit"), None)], EDIT_MATCHERS[name])],
        "Stop": stop["hooks"] if name == "agy" else [stop],
    }
    if name == "claude":
        out["SessionStart"] = [_group([(cmd("start"), None)])]
    return {"hooks": out}


AGY_GROUPS = ("harness-edit", "harness-stop")


def _load_json(path: Path) -> dict[str, Any]:
    """A missing or blank file is empty; a malformed one stops sync so it is not overwritten."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    if not text.strip():
        return {}
    try:
        data = json.loads(text)
    except ValueError as e:
        raise AdapterError(f"{path} is not valid JSON ({e}); fix it, then sync again") from e
    return data if isinstance(data, dict) else {}


def _dump(data: Any) -> str:
    return json.dumps(data, indent=2) + "\n"


def sync(repo: Path, templates: Path, runtime: Path) -> list[str]:
    """Bring a target repo's hook copies and wiring up to the installed harness."""
    repo = repo.resolve()
    result = check(repo, templates=templates, runtime=runtime)
    if result.problems or result.data is None:
        raise AdapterError(f"{repo / FILENAME}: " + "; ".join(result.problems))
    data = result.data
    # Read every agent file before writing any: a malformed one must stop sync
    # with nothing half-applied.
    settings = repo / ".claude/settings.json"
    claude = _load_json(settings)
    codex = _load_json(repo / ".codex/hooks.json")
    agy_file = _load_json(repo / ".agents/hooks.json")
    changes: list[str] = []
    hooks_dir = repo / ".claude/hooks"
    for rel in [h["template"] for h in data["hooks"] if "template" in h] + [WRAPPER]:
        copy = hooks_dir / Path(rel).name
        current = copy.read_text(encoding="utf-8") if copy.is_file() else None
        _write_if_changed(
            copy, _merged((templates / rel).read_text(encoding="utf-8"), current), changes, repo
        )

    wiring = _wiring(data["hooks"])
    # The Claude file's "hooks" belong to agent-harness.json entirely (the repo
    # declares every Claude hook there); its other keys are kept.
    if claude.get("hooks") != wiring["claude"]:
        claude["hooks"] = wiring["claude"]
        _write_if_changed(settings, _dump(claude), changes, repo)
    # Replace only what sync owns (codex's "hooks", agy's harness-* groups) and
    # keep the rest of each file.
    codex["hooks"] = wiring["codex"]["hooks"]
    _write_if_changed(repo / ".codex/hooks.json", _dump(codex), changes, repo)
    agy = {k: v for k, v in agy_file.items() if k not in AGY_GROUPS}
    agy.update(wiring["agy"])
    _write_if_changed(repo / ".agents/hooks.json", _dump(agy), changes, repo)
    committed = bool(changes)  # pack links and info/exclude are not committed files
    _link_pack_skills(repo, data, runtime, changes)

    try:
        installed = json.loads((runtime / "harness-version.json").read_text()).get("short")
    except (OSError, ValueError):
        installed = None
    # Only alongside a real change: a bump alone would leave the repo with an
    # uncommitted change after every unattended update.sh.
    if installed and committed and data["harness"]["version"] != installed:
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


def _shared_parent(repos: list[Path]) -> Path | None:
    """The folder above the registered repos, when a session can start there.

    None at or above HOME, at the filesystem root, or inside a git repo (that
    repo's own skills apply there).
    """
    if not repos:
        return None
    parent = Path(os.path.commonpath([str(r.resolve().parent) for r in repos]))
    home = Path.home().resolve()
    if parent == Path(parent.anchor) or home.is_relative_to(parent):
        return None
    inside = subprocess.run(
        ["git", "-C", str(parent), "rev-parse", "--show-toplevel"],
        capture_output=True,
        check=False,
    )
    return None if inside.returncode == 0 else parent


def sync_all(templates: Path, runtime: Path) -> dict[str, str]:
    """Sync each registered repo: {path: 'missing' | 'up to date' | changes | error}.

    Then link the packs any of them lists into their shared parent folder, so a
    session started there (e.g. ~/projects) sees them too.
    """
    path = runtime / REGISTRY
    report: dict[str, str] = {}
    synced: list[Path] = []
    packs: set[str] = set()
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
        synced.append(Path(entry))
        data = json.loads((Path(entry) / FILENAME).read_text(encoding="utf-8"))
        packs.update(data.get("skill_packs", []))
    ws = _shared_parent(synced)
    if ws is not None:
        changes = []
        _link_pack_skills(ws, {"skill_packs": sorted(packs)}, runtime, changes)
        report[str(ws)] = "workspace: " + (", ".join(changes) if changes else "up to date")
    return report


def unlink_packs(runtime: Path, agent: str) -> list[str]:
    """Undo store-packs for one agent: remove its stored skills and every link to them.

    Run by uninstall.sh. Covers the registered repos and their shared parent.
    """
    store = runtime / PACK_STORE / agent
    path = runtime / REGISTRY
    repos = [
        Path(line.strip())
        for line in (path.read_text().splitlines() if path.is_file() else [])
        if line.strip() and not line.startswith("#") and Path(line.strip()).is_dir()
    ]
    ws = _shared_parent(repos)
    removed: list[str] = []
    for repo in repos + ([ws] if ws else []):
        kept: list[str] = []
        for rel in REPO_SKILL_DIRS:
            d = repo / rel
            for p in sorted(d.iterdir()) if d.is_dir() else []:
                if not p.is_symlink():
                    continue
                target = Path(os.readlink(p))
                if target.is_relative_to(store):
                    p.unlink()
                    removed.append(str(p))
                elif target.is_relative_to(runtime / PACK_STORE):
                    kept.append(f"{rel}/{p.name}")
        _write_exclude(repo, kept, [])
    shutil.rmtree(store, ignore_errors=True)
    return removed


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "command",
        choices=[
            "check",
            "drift",
            "sync",
            "register",
            "sync-all",
            "global-wiring",
            "store-packs",
            "unlink-packs",
        ],
    )
    ap.add_argument("repo", type=Path, nargs="?")
    ap.add_argument("--templates", type=Path, default=HARNESS / "templates/hooks")
    ap.add_argument("--runtime", type=Path, default=None)
    ap.add_argument("--file", type=Path, default=None)
    ap.add_argument("--agent", default=None)
    ap.add_argument("--hooks-dir", type=Path, default=None)
    ap.add_argument("--skills-dir", type=Path, default=None)
    ap.add_argument("--installed", type=Path, default=None)
    ap.add_argument("--repo-dir", type=Path, default=None)
    args = ap.parse_args(argv)
    runtime = args.runtime or _runtime_dir()
    if args.command == "store-packs":
        if not args.agent or args.skills_dir is None:
            ap.error("store-packs needs --agent and --skills-dir")
        installed = None
        if args.installed is not None:
            installed = set(args.installed.read_text(encoding="utf-8").split())
        moved = store_pack_skills(
            args.skills_dir,
            runtime / PACK_STORE / args.agent,
            pack_skill_names(),
            installed=installed,
            repo_dir=args.repo_dir,
        )
        print(f"  pack skills kept out of {args.skills_dir}: {' '.join(moved) or 'none'}")
        return 0
    if args.command == "unlink-packs":
        if not args.agent:
            ap.error("unlink-packs needs --agent")
        removed = unlink_packs(runtime, args.agent)
        print(f"  pack skill links removed for {args.agent}: {len(removed)}")
        return 0
    if args.command == "global-wiring":
        try:
            print(
                _dump(global_wiring(args.agent or "", args.hooks_dir or runtime / "hooks")), end=""
            )
        except AdapterError as e:
            print(f"  FAIL  {e}", file=sys.stderr)
            return 2
        return 0
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
