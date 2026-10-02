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


def test_merge_idempotent_when_existing_entry_is_wrapped(tmp_path):
    """Claude Code writes hooks in {matcher, hooks: [{command}]} form. The
    flat hook.json must dedupe against that wrapped form, not append a duplicate."""
    settings = tmp_path / "settings.json"
    write_json(
        settings,
        {
            "hooks": {
                "UserPromptSubmit": [
                    {"matcher": "", "hooks": [{"type": "command", "command": "polish.py"}]}
                ]
            }
        },
    )
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [{"command": "polish.py"}]}})

    run_helper("--merge", str(hook), str(settings))

    entries = read_json(settings)["hooks"]["UserPromptSubmit"]
    assert len(entries) == 1, f"expected 1 entry, got {entries}"


def test_remove_drops_wrapped_entry(tmp_path):
    """--remove must also handle the wrapped form."""
    settings = tmp_path / "settings.json"
    write_json(
        settings,
        {
            "hooks": {
                "UserPromptSubmit": [
                    {"matcher": "", "hooks": [{"type": "command", "command": "polish.py"}]},
                    {"command": "user-script.sh"},
                ]
            }
        },
    )
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [{"command": "polish.py"}]}})

    run_helper("--remove", str(hook), str(settings))

    entries = read_json(settings)["hooks"]["UserPromptSubmit"]
    assert entries == [{"command": "user-script.sh"}], entries


def test_merge_and_remove_env_keys(tmp_path):
    settings = tmp_path / "settings.json"
    settings.write_text("{}")
    hook = tmp_path / "hook.json"
    write_json(hook, {"env": {"POLISH_REPLACE": "1"}, "hooks": {"UserPromptSubmit": [{"command": "polish.py"}]}})

    run_helper("--merge", str(hook), str(settings))
    data = read_json(settings)
    assert data["env"]["POLISH_REPLACE"] == "1"

    run_helper("--remove", str(hook), str(settings))
    data = read_json(settings)
    assert "env" not in data



def _wrapped(cmd: str) -> dict:
    return {"matcher": "", "hooks": [{"type": "command", "command": cmd}]}


def test_rewire_collapses_stale_copy_into_existing_fresh_entry(tmp_path):
    # A stale-path entry next to the current one used to be rewritten into an
    # identical second entry, so the hook ran twice (seen live in
    # ~/.claude/settings.json, 2026-10-02).
    skills = tmp_path / "skills"
    fresh = f"python3 {skills}/utils/p/lib/p.py"
    stale = "python3 /old/gone/skills/utils/p/lib/p.py"
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [_wrapped(fresh)]}})
    settings = tmp_path / "settings.json"
    write_json(settings, {"hooks": {"UserPromptSubmit": [_wrapped(fresh), _wrapped(stale)]}})

    result = run_helper("--rewire", str(hook), str(settings), "--skills-dir", str(skills))
    assert result.returncode == 0, result.stderr

    assert read_json(settings)["hooks"]["UserPromptSubmit"] == [_wrapped(fresh)]


def test_merge_collapses_existing_duplicate_of_its_own_hook(tmp_path):
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [_wrapped("polish.py")]}})
    settings = tmp_path / "settings.json"
    write_json(settings, {"hooks": {"UserPromptSubmit": [_wrapped("polish.py"), _wrapped("polish.py")]}})

    result = run_helper("--merge", str(hook), str(settings))
    assert result.returncode == 0, result.stderr

    assert read_json(settings)["hooks"]["UserPromptSubmit"] == [_wrapped("polish.py")]


def test_dedupe_leaves_other_hooks_duplicates_alone(tmp_path):
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"UserPromptSubmit": [_wrapped("polish.py")]}})
    settings = tmp_path / "settings.json"
    user = [_wrapped("user.sh"), _wrapped("user.sh")]
    write_json(settings, {"hooks": {"UserPromptSubmit": [*user, _wrapped("polish.py")]}})

    result = run_helper("--merge", str(hook), str(settings))
    assert result.returncode == 0, result.stderr

    assert read_json(settings)["hooks"]["UserPromptSubmit"] == [*user, _wrapped("polish.py")]


def test_gemini_rewire_collapses_duplicate(tmp_path):
    skills = tmp_path / "skills"
    fresh = f"python3 {skills}/utils/p/lib/p.py"
    stale = "python3 /old/gone/skills/utils/p/lib/p.py"
    hook = tmp_path / "hook.json"
    write_json(hook, {"hooks": {"PreInvocation": [{"type": "command", "command": fresh}]}})
    settings = tmp_path / "hooks.json"
    write_json(settings, {"p": {"PreInvocation": [
        {"type": "command", "command": fresh}, {"type": "command", "command": stale}]}})

    result = run_helper("--rewire", str(hook), str(settings), "--skills-dir", str(skills),
                        "--agent", "gemini", "--hook-name", "p")
    assert result.returncode == 0, result.stderr

    assert read_json(settings)["p"]["PreInvocation"] == [{"type": "command", "command": fresh}]
