"""Unit tests for scripts/harness_adapter.py."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import harness_adapter as ha


def _setup(tmp_path: Path) -> tuple[Path, Path, Path]:
    repo, templates, runtime = tmp_path / "repo", tmp_path / "templates", tmp_path / "runtime"
    (templates / "common").mkdir(parents=True)
    (templates / "common/sh-check.sh").write_text("#!/bin/bash\n")
    (repo / ".claude/hooks").mkdir(parents=True)
    (repo / ".claude/hooks/full-validate.sh").write_text("#!/bin/bash\n")
    (repo / "AGENTS.md").write_text("x")
    runtime.mkdir()
    # exists, so only the "stays under templates/" rule can reject ../escape.sh
    (tmp_path / "escape.sh").write_text("#!/bin/bash\n")
    return repo, templates, runtime


def _valid() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "harness": {"source": "agent-skills-setup", "version": "abc1234"},
        "project": {"name": "repo"},
        "state_files": ["AGENTS.md"],
        "verify": ["./init.sh"],
        "hooks": [
            {"template": "common/sh-check.sh", "event": "edit"},
            {"local": ".claude/hooks/full-validate.sh", "event": "stop"},
        ],
    }


def _check(tmp_path: Path, data: Any, raw: str | None = None) -> ha.Result:
    repo, templates, runtime = _setup(tmp_path)
    text = raw if raw is not None else json.dumps(data)
    (repo / ha.FILENAME).write_text(text)
    return ha.check(repo, templates=templates, runtime=runtime)


def test_valid_file_passes(tmp_path: Path) -> None:
    r = _check(tmp_path, _valid())
    assert r.problems == []
    assert r.version_status == "unknown"


def _broken(change: Any) -> dict[str, Any]:
    d = _valid()
    change(d)
    return d


@pytest.mark.parametrize(
    "change, needle",
    [
        (lambda d: d.update(schema_version=2), "schema_version"),
        (lambda d: d.update(extra=1), "unknown key 'extra'"),
        (lambda d: d.pop("verify"), "missing key 'verify'"),
        (lambda d: d.update(verify="./init.sh"), "verify"),
        (lambda d: d.update(verify=[]), "verify"),
        (lambda d: d["hooks"].append({"event": "stop"}), "hooks[2]"),
        (
            lambda d: d["hooks"].append(
                {"template": "common/sh-check.sh", "local": "x", "event": "stop"}
            ),
            "hooks[2]",
        ),
        (lambda d: d["hooks"][0].update(event="PostToolUse"), "event"),
        (lambda d: d["hooks"][0].update(template="common/nope.sh"), "common/nope.sh"),
        (lambda d: d["hooks"][0].update(template="../escape.sh"), "../escape.sh"),
        (lambda d: d["hooks"][1].update(local=".claude/hooks/gone.sh"), "gone.sh"),
        (lambda d: d["state_files"].append("PROGRESS.md"), "PROGRESS.md"),
        (lambda d: d["harness"].pop("version"), "harness"),
    ],
)
def test_each_problem_is_reported(tmp_path: Path, change: Any, needle: str) -> None:
    r = _check(tmp_path, _broken(change))
    assert any(needle in p for p in r.problems), r.problems


def test_missing_and_invalid_file(tmp_path: Path) -> None:
    repo, templates, runtime = _setup(tmp_path)
    assert ha.check(repo, templates=templates, runtime=runtime).problems[0].startswith("no ")
    assert "not valid JSON" in _check(tmp_path / "b", None, raw="{oops").problems[0]


def test_version_in_sync_and_differs(tmp_path: Path) -> None:
    repo, templates, runtime = _setup(tmp_path)
    (repo / ha.FILENAME).write_text(json.dumps(_valid()))
    (runtime / "harness-version.json").write_text(
        json.dumps({"commit": "abc1234ffff", "short": "abc1234"})
    )
    assert ha.check(repo, templates=templates, runtime=runtime).version_status == "in sync"
    (runtime / "harness-version.json").write_text(
        json.dumps({"commit": "def5678ffff", "short": "def5678"})
    )
    r = ha.check(repo, templates=templates, runtime=runtime)
    assert r.version_status == "last changed by abc1234, installed def5678"
    assert r.problems == []


def test_cli_exit_codes(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    repo, templates, runtime = _setup(tmp_path)
    (repo / ha.FILENAME).write_text(json.dumps(_valid()))
    args = [str(repo), "--templates", str(templates), "--runtime", str(runtime)]
    assert ha.main(["check", *args]) == 0
    (repo / ha.FILENAME).write_text(json.dumps(_broken(lambda d: d.update(verify=[]))))
    assert ha.main(["check", *args]) == 2
    assert "verify" in capsys.readouterr().out


TEMPLATE = (
    "#!/bin/bash\n# --- repo config ----------------------------------------\n"
    'SCOPE=""\n# --------------------------------------------------------\necho check\n'
)


def _drift_setup(tmp_path: Path) -> tuple[Path, Path]:
    repo, templates, _ = _setup(tmp_path)
    (templates / "common/sh-check.sh").write_text(TEMPLATE)
    (repo / ".claude/hooks/sh-check.sh").write_text(TEMPLATE.replace('SCOPE=""', 'SCOPE="x"'))
    d = _valid()
    d["hooks"][0]["template"] = "common/sh-check.sh"
    (repo / ha.FILENAME).write_text(json.dumps(d))
    return repo, templates


def test_drift_ignores_the_config_block(tmp_path: Path) -> None:
    repo, templates = _drift_setup(tmp_path)
    assert ha.drift(repo, templates=templates) == []


def test_drift_names_file_and_template(tmp_path: Path) -> None:
    repo, templates = _drift_setup(tmp_path)
    hook = repo / ".claude/hooks/sh-check.sh"
    hook.write_text(hook.read_text().replace("echo check", "echo changed"))
    assert ha.drift(repo, templates=templates) == [
        (".claude/hooks/sh-check.sh", "common/sh-check.sh")
    ]


def test_drift_file_filter_and_cli(tmp_path: Path) -> None:
    repo, templates = _drift_setup(tmp_path)
    hook = repo / ".claude/hooks/sh-check.sh"
    hook.write_text(hook.read_text().replace("echo check", "echo changed"))
    base = ["drift", str(repo), "--templates", str(templates)]
    assert ha.main(base) == 2
    assert ha.main([*base, "--file", str(hook)]) == 2
    assert ha.main([*base, "--file", str(repo / ".claude/hooks/full-validate.sh")]) == 0
    assert ha.main([*base, "--file", str(repo / "AGENTS.md")]) == 0


def _sync_setup(tmp_path: Path) -> tuple[Path, Path, Path]:
    repo, templates, runtime = _setup(tmp_path)
    (templates / "common/sh-check.sh").write_text(TEMPLATE)
    (templates / "common/agent-hook.sh").write_text("#!/bin/bash\n# wrapper\n")
    (repo / ".claude/hooks/sh-check.sh").write_text(
        TEMPLATE.replace('SCOPE=""', 'SCOPE="mine"').replace("echo check", "echo old")
    )
    d = _valid()
    d["hooks"][0]["template"] = "common/sh-check.sh"
    (repo / ha.FILENAME).write_text(json.dumps(d))
    (repo / ".claude/settings.json").write_text('{"permissions": {"deny": ["Bash(x)"]}}')
    (runtime / "harness-version.json").write_text(
        json.dumps({"commit": "def5678ff", "short": "def5678"})
    )
    return repo, templates, runtime


def test_sync_copies_templates_keeping_config_block_and_is_idempotent(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    changes = ha.sync(repo, templates=templates, runtime=runtime)
    hook = (repo / ".claude/hooks/sh-check.sh").read_text()
    assert "echo check" in hook and 'SCOPE="mine"' in hook
    assert (repo / ".claude/hooks/agent-hook.sh").read_text() == "#!/bin/bash\n# wrapper\n"
    assert ".claude/hooks/sh-check.sh" in changes and ".claude/hooks/agent-hook.sh" in changes
    assert json.loads((repo / ha.FILENAME).read_text())["harness"]["version"] == "def5678"
    assert ha.sync(repo, templates=templates, runtime=runtime) == []


def test_sync_bumps_the_version_only_with_a_real_change(tmp_path: Path) -> None:
    # A bump alone would leave every target repo with an uncommitted change after
    # each unattended update.sh, which blocks their own `git pull --ff-only`.
    repo, templates, runtime = _sync_setup(tmp_path)
    ha.sync(repo, templates=templates, runtime=runtime)
    newer = {"commit": "fff0000aa", "short": "fff0000"}
    (runtime / "harness-version.json").write_text(json.dumps(newer))
    assert ha.sync(repo, templates=templates, runtime=runtime) == []
    assert json.loads((repo / ha.FILENAME).read_text())["harness"]["version"] == "def5678"
    # a new pack link is not a committed file either
    (runtime / ha.PACK_STORE / "claude/linear").mkdir(parents=True)
    d = json.loads((repo / ha.FILENAME).read_text())
    d["skill_packs"] = ["tracking"]
    (repo / ha.FILENAME).write_text(json.dumps(d))
    assert ha.sync(repo, templates=templates, runtime=runtime) == [
        ".claude/skills/linear",
        ".agents/skills/linear",
        ".kiro/skills/linear",
    ]
    assert json.loads((repo / ha.FILENAME).read_text())["harness"]["version"] == "def5678"
    (templates / "common/sh-check.sh").write_text(TEMPLATE.replace("echo check", "echo newer"))
    changes = ha.sync(repo, templates=templates, runtime=runtime)
    assert changes == [".claude/hooks/sh-check.sh", ha.FILENAME]
    assert json.loads((repo / ha.FILENAME).read_text())["harness"]["version"] == "fff0000"


ROOT = 'cd "$(git rev-parse --show-toplevel)" && '


def _commands(groups: list[dict[str, Any]]) -> list[str]:
    return [h["command"] for g in groups for h in g["hooks"]]


def test_agent_commands_run_from_the_folder_holding_their_hooks_file(tmp_path: Path) -> None:
    # agy runs a hook with the folder holding hooks.json (.agents/) as its working
    # directory; a command relative to the repo root then exits 127 and agy goes on.
    repo, templates, runtime = _sync_setup(tmp_path)
    log = tmp_path / "calls.log"
    (templates / "common/agent-hook.sh").write_text(f'echo "$PWD $*" >> {log}\n')
    ha.sync(repo, templates=templates, runtime=runtime)
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    agy = json.loads((repo / ".agents/hooks.json").read_text())
    codex = json.loads((repo / ".codex/hooks.json").read_text())["hooks"]
    runs = [
        (repo / ".agents", h["command"])
        for h in agy["harness-stop"]["Stop"]
        + [h for g in agy["harness-edit"]["PostToolUse"] for h in g["hooks"]]
    ] + [(repo / ".codex", c) for ev in ("PostToolUse", "Stop") for c in _commands(codex[ev])]
    for cwd, command in runs:
        r = subprocess.run(["bash", "-c", command], cwd=cwd, input="{}", text=True, check=False)
        assert r.returncode == 0, command
    calls = log.read_text().splitlines()
    assert len(calls) == len(runs) == 4
    assert all(c.startswith(f"{repo.resolve()} ") for c in calls), calls


def test_sync_wires_every_agent_in_order(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    ha.sync(repo, templates=templates, runtime=runtime)
    claude = json.loads((repo / ".claude/settings.json").read_text())
    assert claude["permissions"] == {"deny": ["Bash(x)"]}
    assert claude["hooks"]["PostToolUse"][0]["matcher"] == "Edit|Write|MultiEdit"
    assert _commands(claude["hooks"]["PostToolUse"]) == ["bash .claude/hooks/sh-check.sh"]
    assert _commands(claude["hooks"]["Stop"]) == ["bash .claude/hooks/full-validate.sh"]
    codex = json.loads((repo / ".codex/hooks.json").read_text())["hooks"]
    assert "apply_patch" in codex["PostToolUse"][0]["matcher"]
    assert _commands(codex["PostToolUse"]) == [
        ROOT + "bash .claude/hooks/agent-hook.sh codex edit .claude/hooks/sh-check.sh"
    ]
    assert _commands(codex["Stop"]) == [
        ROOT + "bash .claude/hooks/agent-hook.sh codex stop .claude/hooks/full-validate.sh"
    ]
    agy = json.loads((repo / ".agents/hooks.json").read_text())
    assert _commands(agy["harness-edit"]["PostToolUse"]) == [
        ROOT + "bash .claude/hooks/agent-hook.sh agy edit .claude/hooks/sh-check.sh"
    ]
    # agy nests only tool events under a matcher; any other event is a flat list of
    # hooks, and one nested entry makes agy reject the whole file.
    assert agy["harness-stop"]["Stop"] == [
        {
            "type": "command",
            "command": ROOT
            + "bash .claude/hooks/agent-hook.sh agy stop .claude/hooks/full-validate.sh",
        }
    ]


def test_sync_leaves_matching_claude_settings_untouched(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    ha.sync(repo, templates=templates, runtime=runtime)
    settings = repo / ".claude/settings.json"
    compact = json.dumps(json.loads(settings.read_text()))  # same content, other formatting
    settings.write_text(compact)
    ha.sync(repo, templates=templates, runtime=runtime)
    assert settings.read_text() == compact


def test_sync_refuses_an_invalid_file(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    (repo / ha.FILENAME).write_text("{}")
    with pytest.raises(ha.AdapterError):
        ha.sync(repo, templates=templates, runtime=runtime)


def test_register_and_sync_all(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    ha.register(repo, templates=templates, runtime=runtime)
    ha.register(repo, templates=templates, runtime=runtime)
    lines = (runtime / "target-repos.txt").read_text().splitlines()
    assert lines == [str(repo.resolve())]
    bad = tmp_path / "bad"
    bad.mkdir()
    with pytest.raises(ha.AdapterError):
        ha.register(bad, templates=templates, runtime=runtime)
    with (runtime / "target-repos.txt").open("a") as f:
        f.write(str(tmp_path / "gone") + "\n")
    report = ha.sync_all(templates=templates, runtime=runtime)
    assert report[str(repo.resolve())] != "missing"
    assert report[str(tmp_path / "gone")] == "missing"


def test_drift_covers_the_agent_hook_wrapper(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    ha.sync(repo, templates=templates, runtime=runtime)
    (repo / ".claude/hooks/agent-hook.sh").write_text("#!/bin/bash\n# edited here\n")
    assert (".claude/hooks/agent-hook.sh", "common/agent-hook.sh") in ha.drift(
        repo, templates=templates
    )


def test_sync_writes_no_group_for_an_event_without_hooks(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    d = json.loads((repo / ha.FILENAME).read_text())
    d["hooks"] = [h for h in d["hooks"] if h["event"] == "edit"]
    (repo / ha.FILENAME).write_text(json.dumps(d))
    ha.sync(repo, templates=templates, runtime=runtime)
    assert "Stop" not in json.loads((repo / ".claude/settings.json").read_text())["hooks"]
    assert "Stop" not in json.loads((repo / ".codex/hooks.json").read_text())["hooks"]
    assert list(json.loads((repo / ".agents/hooks.json").read_text())) == ["harness-edit"]


def test_start_hooks_wire_claude_session_start_only(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    (templates / "common/preflight.sh").write_text("#!/bin/bash\n")
    d = json.loads((repo / ha.FILENAME).read_text())
    d["hooks"].append({"template": "common/preflight.sh", "event": "start"})
    (repo / ha.FILENAME).write_text(json.dumps(d))
    # sync runs check first, so this also proves the schema accepts "start"
    ha.sync(repo, templates=templates, runtime=runtime)
    claude = json.loads((repo / ".claude/settings.json").read_text())["hooks"]
    assert _commands(claude["SessionStart"]) == ["bash .claude/hooks/preflight.sh"]
    codex = json.loads((repo / ".codex/hooks.json").read_text())["hooks"]
    assert "SessionStart" not in codex
    assert "preflight" not in (repo / ".agents/hooks.json").read_text()


def test_timeout_is_checked_and_wired(tmp_path: Path) -> None:
    bad = _valid()
    bad["hooks"][1]["timeout"] = "300"
    assert any("timeout" in p for p in _check(tmp_path / "a", bad).problems)
    bad["hooks"][1]["timeout"] = 0
    assert any("timeout" in p for p in _check(tmp_path / "b", bad).problems)
    repo, templates, runtime = _sync_setup(tmp_path / "c")
    d = json.loads((repo / ha.FILENAME).read_text())
    d["hooks"][1]["timeout"] = 300
    (repo / ha.FILENAME).write_text(json.dumps(d))
    ha.sync(repo, templates=templates, runtime=runtime)
    claude = json.loads((repo / ".claude/settings.json").read_text())["hooks"]
    assert claude["Stop"][0]["hooks"][0]["timeout"] == 300
    assert "timeout" not in claude["PostToolUse"][0]["hooks"][0]
    codex = json.loads((repo / ".codex/hooks.json").read_text())["hooks"]
    assert codex["Stop"][0]["hooks"][0]["timeout"] == 300
    agy = json.loads((repo / ".agents/hooks.json").read_text())
    assert agy["harness-stop"]["Stop"][0]["timeout"] == 300


@pytest.mark.parametrize(
    "packs, ok", [(["tracking"], True), (["nope"], False), (["core"], False), ("tracking", False)]
)
def test_skill_packs_are_checked(tmp_path: Path, packs: Any, ok: bool) -> None:
    d = _valid()
    d["skill_packs"] = packs
    problems = _check(tmp_path, d).problems
    assert (problems == []) is ok, problems


def test_global_wiring_per_agent() -> None:
    claude = ha.global_wiring("claude", Path("/rt/hooks"))["hooks"]
    assert claude["PostToolUse"] == [
        {
            "matcher": "Edit|Write|MultiEdit",
            "hooks": [
                {"type": "command", "command": 'bash "/rt/hooks/global-hook.sh" claude edit'}
            ],
        }
    ]
    assert _commands(claude["Stop"]) == ['bash "/rt/hooks/global-hook.sh" claude stop']
    assert claude["Stop"][0]["hooks"][0]["timeout"] == 120
    assert _commands(claude["SessionStart"]) == ['bash "/rt/hooks/global-hook.sh" claude start']
    codex = ha.global_wiring("codex", Path("/rt/hooks"))["hooks"]
    assert "apply_patch" in codex["PostToolUse"][0]["matcher"]
    assert _commands(codex["Stop"]) == ['bash "/rt/hooks/global-hook.sh" codex stop']
    assert "SessionStart" not in codex
    # install.sh names agy "gemini"; agy takes Stop as a flat list of hooks
    agy = ha.global_wiring("gemini", Path("/rt/hooks"))["hooks"]
    assert agy["PostToolUse"][0]["matcher"] == "replace_file_content|write_to_file"
    assert _commands(agy["PostToolUse"]) == ['bash "/rt/hooks/global-hook.sh" agy edit']
    assert agy["Stop"] == [
        {"type": "command", "command": 'bash "/rt/hooks/global-hook.sh" agy stop', "timeout": 120}
    ]
    assert "SessionStart" not in agy
    with pytest.raises(ha.AdapterError):
        ha.global_wiring("kiro", Path("/rt/hooks"))


def test_global_wiring_cli_prints_json(capsys: pytest.CaptureFixture[str]) -> None:
    assert ha.main(["global-wiring", "--agent", "gemini", "--hooks-dir", "/rt/hooks"]) == 0
    assert json.loads(capsys.readouterr().out) == ha.global_wiring("gemini", Path("/rt/hooks"))


def test_store_pack_skills_moves_only_pack_skills_and_is_repeatable(tmp_path: Path) -> None:
    skills, store, src = tmp_path / "skills", tmp_path / "store", tmp_path / "src"
    (src / "linear").mkdir(parents=True)
    (skills / "kanban-ai").mkdir(parents=True)
    (skills / "kanban-ai/SKILL.md").write_text("k")
    (skills / "brainstorming").mkdir()
    (skills / "linear").symlink_to(src / "linear")
    assert ha.store_pack_skills(skills, store, {"linear", "kanban-ai", "absent"}) == [
        "kanban-ai",
        "linear",
    ]
    assert sorted(p.name for p in skills.iterdir()) == ["brainstorming"]
    assert (store / "linear").is_symlink() and (store / "linear").resolve() == src / "linear"
    assert (store / "kanban-ai/SKILL.md").read_text() == "k"
    # the next install puts them back globally; storing again replaces the stored copy
    (skills / "kanban-ai").mkdir()
    (skills / "kanban-ai/SKILL.md").write_text("k2")
    assert ha.store_pack_skills(skills, store, {"kanban-ai"}) == ["kanban-ai"]
    assert (store / "kanban-ai/SKILL.md").read_text() == "k2"


def test_store_pack_skills_leaves_a_same_name_skill_the_install_did_not_put_there(
    tmp_path: Path,
) -> None:
    skills, store, repo = tmp_path / "skills", tmp_path / "store", tmp_path / "harness"
    (repo / "skills/x/review").mkdir(parents=True)
    (tmp_path / "other/testing").mkdir(parents=True)
    (skills / "audit").mkdir(parents=True)  # the user's own skill, not installed by this run
    (skills / "audit/SKILL.md").write_text("mine")
    (skills / "testing").symlink_to(tmp_path / "other/testing")  # another tool's link
    (skills / "review").symlink_to(repo / "skills/x/review")
    moved = ha.store_pack_skills(
        skills, store, {"audit", "testing", "review"},
        installed={"review", "testing"}, repo_dir=repo,
    )
    assert moved == ["review"]
    assert (skills / "audit/SKILL.md").read_text() == "mine"
    assert (skills / "testing").resolve() == tmp_path / "other/testing"
    assert not (store / "audit").exists() and not (store / "testing").exists()


@pytest.mark.parametrize("rel", [".claude/settings.json", ".codex/hooks.json", ".agents/hooks.json"])
def test_sync_refuses_to_overwrite_a_malformed_agent_file(tmp_path: Path, rel: str) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    ha.sync(repo, templates=templates, runtime=runtime)
    bad = '{"permissions": {"allow": ["Bash(ls)"]},}\n'  # trailing comma from a hand edit
    (repo / rel).write_text(bad)
    with pytest.raises(ha.AdapterError, match="not valid JSON"):
        ha.sync(repo, templates=templates, runtime=runtime)
    assert (repo / rel).read_text() == bad


def test_sync_writes_nothing_when_one_agent_file_is_malformed(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    ha.sync(repo, templates=templates, runtime=runtime)
    claude = repo / ".claude/settings.json"
    claude.write_text('{"hooks": {}}\n')  # sync would rewrite this
    (repo / ".agents/hooks.json").write_text("{,}")
    with pytest.raises(ha.AdapterError):
        ha.sync(repo, templates=templates, runtime=runtime)
    assert claude.read_text() == '{"hooks": {}}\n'


def test_sync_treats_an_empty_agent_file_as_empty(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    (repo / ".codex").mkdir(exist_ok=True)
    (repo / ".codex/hooks.json").write_text("")
    ha.sync(repo, templates=templates, runtime=runtime)
    assert "hooks" in json.loads((repo / ".codex/hooks.json").read_text())


def _exclude(repo: Path) -> str:
    return (repo / ".git/info/exclude").read_text()


def test_sync_links_listed_pack_skills_for_every_agent_and_unlinks_dropped_ones(
    tmp_path: Path,
) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    store = runtime / ha.PACK_STORE
    for agent in ("claude", "gemini"):
        (store / agent / "linear").mkdir(parents=True)
    (repo / ".claude/skills/own").mkdir(parents=True)
    d = json.loads((repo / ha.FILENAME).read_text())
    d["skill_packs"] = ["tracking"]
    (repo / ha.FILENAME).write_text(json.dumps(d))
    changes = ha.sync(repo, templates=templates, runtime=runtime)
    assert os.readlink(repo / ".claude/skills/linear") == str(store / "claude/linear")
    assert os.readlink(repo / ".agents/skills/linear") == str(store / "gemini/linear")
    # no kiro copy on this host: any agent's copy is the same skill
    assert (repo / ".kiro/skills/linear").resolve() in {
        (store / a / "linear").resolve() for a in ("claude", "gemini")
    }
    assert ".claude/skills/linear" in changes
    assert not (repo / ".claude/skills/kanban-ai").exists()  # not in the store: skipped
    for rel in (".claude/skills/linear", ".agents/skills/linear", ".kiro/skills/linear"):
        assert f"/{rel}\n" in _exclude(repo)
    assert ha.sync(repo, templates=templates, runtime=runtime) == []
    d["skill_packs"] = []
    (repo / ha.FILENAME).write_text(json.dumps(d))
    ha.sync(repo, templates=templates, runtime=runtime)
    for rel in (".claude/skills", ".agents/skills", ".kiro/skills"):
        assert not (repo / rel / "linear").is_symlink()
    assert (repo / ".claude/skills/own").is_dir()
    assert "skills/linear" not in _exclude(repo)


def test_a_repo_skill_of_the_same_name_is_never_replaced(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    (runtime / ha.PACK_STORE / "claude/linear").mkdir(parents=True)
    (repo / ".claude/skills/linear").mkdir(parents=True)
    (repo / ".claude/skills/linear/SKILL.md").write_text("repo's own")
    d = json.loads((repo / ha.FILENAME).read_text())
    d["skill_packs"] = ["tracking"]
    (repo / ha.FILENAME).write_text(json.dumps(d))
    ha.sync(repo, templates=templates, runtime=runtime)
    assert not (repo / ".claude/skills/linear").is_symlink()
    assert (repo / ".claude/skills/linear/SKILL.md").read_text() == "repo's own"


def _two_repos(ws: Path) -> tuple[Path, Path, Path, Path]:
    a, templates, runtime = _sync_setup(ws / "a")
    b, _, _ = _sync_setup(ws / "b")
    for repo, packs in ((a, ["tracking"]), (b, ["ai"])):
        d = json.loads((repo / ha.FILENAME).read_text())
        d["skill_packs"] = packs
        (repo / ha.FILENAME).write_text(json.dumps(d))
    for name in ("linear", "kanban-ai", "ai-stack"):
        (runtime / ha.PACK_STORE / "claude" / name).mkdir(parents=True)
    (runtime / ha.REGISTRY).write_text(f"{a}\n{b}\n")
    return a, b, templates, runtime


def test_sync_all_links_every_listed_pack_into_the_repos_shared_parent(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # A session started in the folder above the repos (~/projects) loads that
    # folder's skills, not the repos'.
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    ws = tmp_path / "ws"
    a, b, templates, runtime = _two_repos(ws)
    report = ha.sync_all(templates=templates, runtime=runtime)
    for rel in (".claude/skills", ".agents/skills", ".kiro/skills"):
        assert sorted(p.name for p in (ws / rel).iterdir()) == ["ai-stack", "kanban-ai", "linear"]
    assert sorted(p.name for p in (a / ".claude/skills").iterdir()) == ["kanban-ai", "linear"]
    assert report[str(ws)].startswith("workspace: ")
    d = json.loads((b / ha.FILENAME).read_text())
    d["skill_packs"] = []
    (b / ha.FILENAME).write_text(json.dumps(d))
    ha.sync_all(templates=templates, runtime=runtime)
    assert sorted(p.name for p in (ws / ".claude/skills").iterdir()) == ["kanban-ai", "linear"]


@pytest.mark.parametrize("case", ["home", "git"])
def test_no_shared_parent_links_at_home_or_inside_a_repo(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, case: str
) -> None:
    ws = tmp_path / "ws"
    monkeypatch.setenv("HOME", str(ws if case == "home" else tmp_path / "home"))
    _, _, templates, runtime = _two_repos(ws)
    if case == "git":
        subprocess.run(["git", "init", "-q", str(ws)], check=True)
    report = ha.sync_all(templates=templates, runtime=runtime)
    assert not (ws / ".claude/skills").exists()
    assert str(ws) not in report


def test_unlink_packs_removes_one_agents_store_and_every_link_into_it(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    ws = tmp_path / "ws"
    a, b, templates, runtime = _two_repos(ws)
    subprocess.run(["git", "init", "-q", str(a)], check=True)
    (runtime / ha.PACK_STORE / "gemini/linear").mkdir(parents=True)
    ha.sync_all(templates=templates, runtime=runtime)
    assert "/.claude/skills/linear\n" in _exclude(a)
    removed = ha.unlink_packs(runtime, "claude")
    assert not (runtime / ha.PACK_STORE / "claude").exists()
    assert (runtime / ha.PACK_STORE / "gemini/linear").is_dir()
    for repo in (a, b, ws):
        for rel in (".claude/skills", ".kiro/skills"):
            assert not any((repo / rel).iterdir()) if (repo / rel).is_dir() else True
    # agy's link points at agy's own copy and stays
    assert os.readlink(a / ".agents/skills/linear") == str(
        runtime / ha.PACK_STORE / "gemini/linear"
    )
    assert f"{a}/.claude/skills/linear" in removed
    assert "/.claude/skills/linear\n" not in _exclude(a)
    assert "/.agents/skills/linear\n" in _exclude(a)


def test_sync_keeps_what_it_does_not_own_in_the_agy_and_codex_files(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    mine = {"PreInvocation": [{"type": "command", "command": "echo mine"}]}
    (repo / ".agents").mkdir()
    (repo / ".agents/hooks.json").write_text(
        json.dumps({"repo-own": mine, "harness-edit": {"PostToolUse": []}})
    )
    (repo / ".codex").mkdir()
    (repo / ".codex/hooks.json").write_text(json.dumps({"note": "kept", "hooks": {"Old": []}}))
    ha.sync(repo, templates=templates, runtime=runtime)
    agy = json.loads((repo / ".agents/hooks.json").read_text())
    assert agy["repo-own"] == mine
    assert set(agy) == {"repo-own", "harness-edit", "harness-stop"}
    codex = json.loads((repo / ".codex/hooks.json").read_text())
    assert codex["note"] == "kept" and "Old" not in codex["hooks"]
    # no stop hooks any more: the harness group goes, the repo's own stays
    d = json.loads((repo / ha.FILENAME).read_text())
    d["hooks"] = [h for h in d["hooks"] if h["event"] != "stop"]
    (repo / ha.FILENAME).write_text(json.dumps(d))
    ha.sync(repo, templates=templates, runtime=runtime)
    assert set(json.loads((repo / ".agents/hooks.json").read_text())) == {
        "repo-own",
        "harness-edit",
    }


def test_a_repo_skill_that_is_its_own_symlink_is_never_replaced(tmp_path: Path) -> None:
    repo, templates, runtime = _sync_setup(tmp_path)
    (runtime / ha.PACK_STORE / "claude/linear").mkdir(parents=True)
    shared = tmp_path / "shared/linear"
    shared.mkdir(parents=True)
    (repo / ".claude/skills").mkdir(parents=True)
    (repo / ".claude/skills/linear").symlink_to(shared)
    d = json.loads((repo / ha.FILENAME).read_text())
    d["skill_packs"] = ["tracking"]
    (repo / ha.FILENAME).write_text(json.dumps(d))
    ha.sync(repo, templates=templates, runtime=runtime)
    assert os.readlink(repo / ".claude/skills/linear") == str(shared)
