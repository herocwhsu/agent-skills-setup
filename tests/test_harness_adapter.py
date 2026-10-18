"""Unit tests for scripts/harness_adapter.py."""

from __future__ import annotations

import json
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
    assert r.version_status == "differs: repo synced at abc1234, installed def5678"
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
