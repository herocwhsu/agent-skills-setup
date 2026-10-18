"""Unit tests for scripts/repo_audit.py."""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import repo_audit as ra

TEMPLATE = """#!/usr/bin/env bash
set -euo pipefail

# --- repo config --------------------------------------------------------------
SCOPE=""
# -------------------------------------------------------------------------------

echo check
"""


def _write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def _skill(root: Path, name: str, desc: str, body: str) -> None:
    _write(root / name / "SKILL.md", f"---\nname: {name}\ndescription: {desc}\n---\n{body}")


def _setup(tmp_path: Path) -> tuple[Path, Path, Path]:
    home, repo, templates = tmp_path / "home", tmp_path / "repo", tmp_path / "templates"
    _write(home / ".claude/CLAUDE.md", "g" * 400)
    _write(repo / "CLAUDE.md", "@AGENTS.md\n@AGENTS.md\n")
    _write(repo / "AGENTS.md", "a" * 800)
    _skill(home / ".claude/skills", "alpha", "d" * 40, "B" * 4000)
    _skill(repo / ".claude/skills", "beta", "e" * 80, "C" * 4000)
    _write(templates / "common/same.sh", TEMPLATE)
    _write(templates / "k8s/stale.sh", TEMPLATE)
    _write(repo / ".claude/hooks/same.sh", TEMPLATE.replace('SCOPE=""', 'SCOPE="svc/**"'))
    _write(repo / ".claude/hooks/stale.sh", TEMPLATE.replace("echo check", "echo old"))
    _write(repo / ".claude/hooks/mine.sh", "#!/bin/bash\n")
    return home, repo, templates


def _audit(tmp_path: Path) -> dict:
    home, repo, templates = _setup(tmp_path)
    return ra.audit(repo, home=home, templates=templates)


def test_always_loaded_counts_rules_imports_and_skill_descriptions_not_bodies(
    tmp_path: Path,
) -> None:
    loaded = _audit(tmp_path)["always_loaded"]
    files = {f["file"]: f for f in loaded["files"]}
    assert files["~/.claude/CLAUDE.md"]["tokens"] == 100
    assert files["AGENTS.md"]["tokens"] == 200
    assert sum(1 for f in loaded["files"] if f["file"] == "AGENTS.md") == 1
    skills = {s["name"]: s for s in loaded["skills"]}
    assert set(skills) == {"alpha", "beta"}
    assert skills["beta"]["source"] == "repo"
    assert loaded["skill_tokens"] < 100  # bodies are 2,000 tokens; never counted
    assert loaded["tokens"] == loaded["skill_tokens"] + sum(
        f["tokens"] or 0 for f in loaded["files"]
    )
    assert loaded["estimate"] == "chars/4"


def test_state_files_only_when_present(tmp_path: Path) -> None:
    home, repo, templates = _setup(tmp_path)
    assert ra.audit(repo, home=home, templates=templates)["state_files"] == []
    _write(repo / "PROGRESS.md", "p" * 1200)
    state = ra.audit(repo, home=home, templates=templates)["state_files"]
    assert state == [{"file": "PROGRESS.md", "tokens": 300}]


def test_hooks_identical_drifted_local(tmp_path: Path) -> None:
    hooks = {h["file"]: h for h in _audit(tmp_path)["hooks"]}
    assert hooks["same.sh"] == {
        "file": "same.sh",
        "status": "identical",
        "template": "common/same.sh",
    }
    assert hooks["stale.sh"]["status"] == "drifted"
    assert hooks["stale.sh"]["template"] == "k8s/stale.sh"
    assert hooks["mine.sh"] == {"file": "mine.sh", "status": "local", "template": None}


def test_agents_wired_only_with_a_hook_command(tmp_path: Path) -> None:
    home, repo, templates = _setup(tmp_path)
    cmd = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "x.sh"}]}]}}
    _write(repo / ".claude/settings.json", json.dumps(cmd))
    _write(repo / ".codex/hooks.json", json.dumps({"hooks": {}}))
    _write(repo / ".agents/hooks.json", "{not json")
    agents = ra.audit(repo, home=home, templates=templates)["agent_hooks"]
    assert agents == {"claude": True, "codex": False, "agy": False}
    # agy groups hooks under a name: {"<name>": {"PostToolUse": [...]}}
    _write(repo / ".agents/hooks.json", json.dumps({"sh": cmd["hooks"]}))
    assert ra.audit(repo, home=home, templates=templates)["agent_hooks"]["agy"] is True


def test_missing_file_is_missing_not_zero(tmp_path: Path) -> None:
    home, repo, templates = _setup(tmp_path)
    (repo / "AGENTS.md").unlink()
    files = {
        f["file"]: f
        for f in ra.audit(repo, home=home, templates=templates)["always_loaded"]["files"]
    }
    assert files["AGENTS.md"] == {"file": "AGENTS.md", "tokens": None, "status": "missing"}


def test_save_writes_dated_baseline(tmp_path: Path) -> None:
    home, repo, templates = _setup(tmp_path)
    report = ra.audit(repo, home=home, templates=templates)
    out = ra.save(report, tmp_path / "telemetry", today="2026-10-17")
    assert out == tmp_path / "telemetry/repo/2026-10-17.json"
    assert json.loads(out.read_text())["repo"] == "repo"


def test_scoped_skill_tokens_count_core_packs_unassigned_and_repo(tmp_path: Path) -> None:
    home, repo, templates = _setup(tmp_path)
    _skill(home / ".claude/skills", "gamma", "g" * 400, "")
    _skill(home / ".claude/skills", "delta", "h" * 800, "")
    _skill(home / ".claude/skills", "free", "f" * 40, "")
    packs = {"core": ["alpha"], "p1": ["gamma"], "p2": ["delta"]}
    _write(repo / "agent-harness.json", json.dumps({"skill_packs": ["p1"]}))
    loaded = ra.audit(repo, home=home, templates=templates, packs=packs)["always_loaded"]
    by = {s["name"]: s for s in loaded["skills"]}
    assert (
        by["alpha"]["pack"] == "core" and by["delta"]["pack"] == "p2" and by["free"]["pack"] is None
    )
    scoped = sum(by[n]["tokens"] for n in ("alpha", "gamma", "free", "beta"))
    assert loaded["skill_tokens_scoped"] == scoped
    assert loaded["skill_tokens"] - loaded["skill_tokens_scoped"] == by["delta"]["tokens"]


def test_pack_file_is_consistent() -> None:
    packs = ra.load_packs()
    names = [n for k, v in packs.items() for n in v]
    assert "core" in packs and len(names) == len(set(names))
