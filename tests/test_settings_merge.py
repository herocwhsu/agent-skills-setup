"""Tests for scripts/_settings_merge.py."""
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
HELPER = REPO_ROOT / "scripts" / "_settings_merge.py"


def run_helper(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(HELPER), *args],
        capture_output=True,
        text=True,
    )


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data))


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def test_merge_into_empty_settings(tmp_path):
    settings = tmp_path / "settings.json"
    settings.write_text("{}")
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [{"command": "polish.py"}]}})

    result = run_helper("--merge", str(hook), str(settings))
    assert result.returncode == 0, result.stderr

    data = read_json(settings)
    assert data["hooks"]["UserPromptSubmit"] == [{"command": "polish.py"}]


def test_merge_preserves_other_keys(tmp_path):
    settings = tmp_path / "settings.json"
    write_json(settings, {"theme": "dark", "hooks": {"OtherEvent": [{"command": "x"}]}})
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [{"command": "polish.py"}]}})

    run_helper("--merge", str(hook), str(settings))

    data = read_json(settings)
    assert data["theme"] == "dark"
    assert data["hooks"]["OtherEvent"] == [{"command": "x"}]
    assert data["hooks"]["UserPromptSubmit"] == [{"command": "polish.py"}]


def test_merge_is_idempotent(tmp_path):
    settings = tmp_path / "settings.json"
    settings.write_text("{}")
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [{"command": "polish.py"}]}})

    run_helper("--merge", str(hook), str(settings))
    run_helper("--merge", str(hook), str(settings))

    data = read_json(settings)
    assert data["hooks"]["UserPromptSubmit"] == [{"command": "polish.py"}]


def test_merge_keeps_existing_user_hook(tmp_path):
    settings = tmp_path / "settings.json"
    write_json(
        settings,
        {"hooks": {"UserPromptSubmit": [{"command": "user-script.sh"}]}},
    )
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [{"command": "polish.py"}]}})

    run_helper("--merge", str(hook), str(settings))

    cmds = [h["command"] for h in read_json(settings)["hooks"]["UserPromptSubmit"]]
    assert "user-script.sh" in cmds
    assert "polish.py" in cmds


def test_remove_hook_only_drops_matching_entry(tmp_path):
    settings = tmp_path / "settings.json"
    write_json(
        settings,
        {"hooks": {"UserPromptSubmit": [{"command": "polish.py"}, {"command": "user-script.sh"}]}},
    )
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [{"command": "polish.py"}]}})

    run_helper("--remove", str(hook), str(settings))

    cmds = [h["command"] for h in read_json(settings)["hooks"]["UserPromptSubmit"]]
    assert cmds == ["user-script.sh"]


def test_remove_when_settings_missing_is_noop(tmp_path):
    settings = tmp_path / "settings.json"
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [{"command": "polish.py"}]}})

    result = run_helper("--remove", str(hook), str(settings))
    assert result.returncode == 0, result.stderr
    assert not settings.exists()
