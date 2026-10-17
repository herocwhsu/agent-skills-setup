#!/usr/bin/env python3
"""Measure what a target repo costs and carries for an agent session.

Reports, as JSON:
  always_loaded  global CLAUDE.md, the repo's CLAUDE.md and every file it
                 @-imports, and the name+description of each global and repo
                 skill (bodies load only on use, so they are not counted)
  state_files    PROGRESS.md and feature_list.json, when present
  hooks          each .claude/hooks file: identical / drifted against the
                 same-named file under templates/hooks/<stack>/ (the repo
                 config block ignored), or local when no template has its name
  agent_hooks    which agents have at least one hook command wired

Tokens are estimates (chars/4). A missing file is reported as missing, never 0.

Usage: repo_audit.py <repo> [--save]
  --save  also write docs/telemetry/repos/<repo>/<YYYY-MM-DD>.json here
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from pathlib import Path
from typing import Any

HARNESS = Path(__file__).resolve().parent.parent
STATE_FILES = ("PROGRESS.md", "feature_list.json")
AGENT_SETTINGS = {
    "claude": ".claude/settings.json",
    "codex": ".codex/hooks.json",
    "agy": ".agents/hooks.json",
}
IMPORT_RE = re.compile(r"^@(\S+)\s*$")
CONFIG_START = "# --- repo config"
CONFIG_END_RE = re.compile(r"^# -{10,}\s*$")


def _tokens(text: str) -> int:
    return len(text) // 4


def _read(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def _label(path: Path, repo: Path, home: Path) -> str:
    for base, prefix in ((repo, ""), (home, "~/")):
        try:
            return prefix + str(path.relative_to(base))
        except ValueError:
            continue
    return str(path)


def _file_entry(path: Path, repo: Path, home: Path) -> dict[str, Any]:
    text = _read(path)
    label = _label(path, repo, home)
    if text is None:
        return {"file": label, "tokens": None, "status": "missing"}
    return {"file": label, "tokens": _tokens(text)}


def _instruction_files(repo: Path, home: Path) -> list[Path]:
    """Global CLAUDE.md, then the repo CLAUDE.md and its @imports, each once."""
    out: list[Path] = [home / ".claude/CLAUDE.md"]
    queue = [repo / "CLAUDE.md"]
    while queue:
        path = queue.pop(0)
        if path in out:
            continue
        out.append(path)
        for line in (_read(path) or "").splitlines():
            m = IMPORT_RE.match(line.strip())
            if m:
                ref = m.group(1)
                target = home / ref[2:] if ref.startswith("~/") else path.parent / ref
                queue.append(target.resolve() if target.exists() else target)
    return out


def _skill_header(text: str) -> str:
    """The name and description lines of a SKILL.md front matter."""
    m = re.match(r"---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return ""
    keep: list[str] = []
    inside = False
    for line in m.group(1).splitlines():
        if re.match(r"^[\w-]+:", line):
            inside = line.split(":", 1)[0] in ("name", "description")
        if inside:
            keep.append(line)
    return "\n".join(keep)


def _skills(repo: Path, home: Path) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for source, root in (("global", home / ".claude/skills"), ("repo", repo / ".claude/skills")):
        if not root.is_dir():
            continue
        for skill in sorted(root.iterdir()):
            text = _read(skill / "SKILL.md")
            if text is not None:
                out.append(
                    {"name": skill.name, "source": source, "tokens": _tokens(_skill_header(text))}
                )
    return out


def _strip_config(text: str) -> str:
    out: list[str] = []
    inside = False
    for line in text.splitlines():
        if line.startswith(CONFIG_START):
            inside = True
            continue
        if inside:
            inside = not CONFIG_END_RE.match(line)
            continue
        out.append(line)
    return "\n".join(out)


def _hooks(repo: Path, templates: Path) -> list[dict[str, Any]]:
    index: dict[str, Path] = {}
    if templates.is_dir():
        for path in sorted(templates.glob("*/*")):
            if path.is_file():
                index.setdefault(path.name, path)
    hooks_dir = repo / ".claude/hooks"
    out: list[dict[str, Any]] = []
    if not hooks_dir.is_dir():
        return out
    for hook in sorted(p for p in hooks_dir.iterdir() if p.is_file()):
        tmpl = index.get(hook.name)
        if tmpl is None:
            out.append({"file": hook.name, "status": "local", "template": None})
            continue
        same = _strip_config(_read(hook) or "") == _strip_config(_read(tmpl) or "")
        out.append(
            {
                "file": hook.name,
                "status": "identical" if same else "drifted",
                "template": str(tmpl.relative_to(templates)),
            }
        )
    return out


def _has_command(node: Any) -> bool:
    if isinstance(node, dict):
        if node.get("type") == "command" and node.get("command"):
            return True
        return any(_has_command(v) for v in node.values())
    if isinstance(node, list):
        return any(_has_command(v) for v in node)
    return False


def _agent_hooks(repo: Path) -> dict[str, bool]:
    out: dict[str, bool] = {}
    for agent, rel in AGENT_SETTINGS.items():
        try:
            data = json.loads(_read(repo / rel) or "null")
        except ValueError:
            data = None
        out[agent] = _has_command(data)
    return out


def audit(repo: Path, home: Path, templates: Path) -> dict[str, Any]:
    repo = repo.resolve()
    files = [_file_entry(p, repo, home) for p in _instruction_files(repo, home)]
    skills = _skills(repo, home)
    skill_tokens = sum(s["tokens"] for s in skills)
    return {
        "schema_version": 1,
        "repo": repo.name,
        "always_loaded": {
            "estimate": "chars/4",
            "tokens": skill_tokens + sum(f["tokens"] or 0 for f in files),
            "files": files,
            "skill_tokens": skill_tokens,
            "skills": skills,
        },
        "state_files": [
            {"file": name, "tokens": _tokens(text)}
            for name in STATE_FILES
            if (text := _read(repo / name)) is not None
        ],
        "hooks": _hooks(repo, templates),
        "agent_hooks": _agent_hooks(repo),
    }


def save(report: dict[str, Any], out_root: Path, today: str | None = None) -> Path:
    day = today or datetime.datetime.now().astimezone().date().isoformat()
    out = out_root / report["repo"] / f"{day}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("repo", type=Path)
    ap.add_argument("--save", action="store_true")
    args = ap.parse_args(argv)
    if not args.repo.is_dir():
        print(f"repo_audit: not a directory: {args.repo}", file=sys.stderr)
        return 2
    report = audit(args.repo, home=Path.home(), templates=HARNESS / "templates/hooks")
    print(json.dumps(report, indent=2))
    if args.save:
        print(f"saved {save(report, HARNESS / 'docs/telemetry/repos')}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
