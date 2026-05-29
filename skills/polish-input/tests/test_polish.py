from __future__ import annotations

"""Unit tests for polish.py — skip rules."""
import os
import subprocess
import sys
from pathlib import Path

POLISH = Path(__file__).resolve().parents[1] / "lib" / "polish.py"


def run_polish(stdin_text: str, env_overrides: dict | None = None) -> tuple[str, str, int]:
    """Run polish.py as a subprocess. Returns (stdout, stderr, returncode)."""
    env = os.environ.copy()
    # Strip any POLISH_* vars from the host env so tests are deterministic.
    for k in [k for k in env if k.startswith("POLISH_")]:
        del env[k]
    # Default: ensure tests don't accidentally hit a real engine install.
    env["POLISH_TEST_NO_ENGINE"] = "1"
    if env_overrides:
        env.update(env_overrides)
    proc = subprocess.run(
        [sys.executable, str(POLISH)],
        input=stdin_text,
        capture_output=True,
        text=True,
        env=env,
    )
    return proc.stdout, proc.stderr, proc.returncode


def test_slash_command_skips():
    out, err, code = run_polish("/help")
    assert out == "/help"
    assert err == ""
    assert code == 0


def test_multi_line_skips():
    out, err, code = run_polish("first line\nsecond line")
    assert out == "first line\nsecond line"
    assert err == ""
    assert code == 0


def test_over_length_skips():
    long_text = "a " * 2001  # 4002 chars
    out, err, code = run_polish(long_text)
    assert out == long_text
    assert err == ""
    assert code == 0


def test_disable_env_skips():
    out, err, code = run_polish("i want add login", env_overrides={"POLISH_DISABLE": "1"})
    assert out == "i want add login"
    assert err == ""
    assert code == 0


def test_empty_input_skips():
    out, err, code = run_polish("")
    assert out == ""
    assert err == ""
    assert code == 0


import json


def _fake_response(mapping: dict[str, str]) -> dict[str, str]:
    """Return env overrides that inject a fake engine response map."""
    return {"POLISH_TEST_FAKE_RESPONSE": json.dumps(mapping), "POLISH_TEST_NO_ENGINE": ""}


def test_changed_text_emits_stderr_and_keeps_stdout_original():
    fake = _fake_response({"i want add login": "I want to add a login."})
    out, err, code = run_polish("i want add login", env_overrides=fake)
    assert out == "i want add login"
    assert "[polish]" in err
    assert "I want to add a login." in err
    assert code == 0


def test_unchanged_text_emits_no_stderr():
    fake = _fake_response({"Read the auth file.": "Read the auth file."})
    out, err, code = run_polish("Read the auth file.", env_overrides=fake)
    assert out == "Read the auth file."
    assert err == ""
    assert code == 0


def test_replace_mode_sends_polished_to_stdout():
    fake = _fake_response({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_REPLACE": "1"}
    out, err, code = run_polish("i want add login", env_overrides=overrides)
    assert out == "I want to add a login."
    assert "[polish]" in err
    assert code == 0


def test_engine_error_fails_open():
    overrides = {"POLISH_TEST_FAKE_RESPONSE": "RAISE", "POLISH_TEST_NO_ENGINE": ""}
    out, err, code = run_polish("i want add login", env_overrides=overrides)
    assert out == "i want add login"
    assert err == ""
    assert code == 0


def test_display_line_default():
    fake = _fake_response({"i want add login": "I want to add a login."})
    _, err, _ = run_polish("i want add login", env_overrides=fake)
    assert err == "[polish] I want to add a login.\n"


def test_display_diff_shows_word_changes():
    fake = _fake_response({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_DISPLAY": "diff"}
    _, err, _ = run_polish("i want add login", env_overrides=overrides)
    assert err.startswith("[polish] ")
    # Diff format must show added "to" and "a" or removed "i" somehow.
    assert "+" in err or "-" in err


def test_display_box_wraps_in_borders():
    fake = _fake_response({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_DISPLAY": "box"}
    _, err, _ = run_polish("i want add login", env_overrides=overrides)
    # Box must contain some border character on lines and the polished text.
    assert "I want to add a login." in err
    lines = err.strip().split("\n")
    assert len(lines) >= 3  # top border, content, bottom border


def test_display_invalid_falls_back_to_line():
    fake = _fake_response({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_DISPLAY": "nonsense"}
    _, err, _ = run_polish("i want add login", env_overrides=overrides)
    assert err == "[polish] I want to add a login.\n"


def test_engine_error_writes_one_time_hint_to_debug_log(tmp_path):
    state_dir = tmp_path / "state"
    overrides = {
        "POLISH_TEST_FAKE_RESPONSE": "RAISE",
        "POLISH_TEST_NO_ENGINE": "",
        "POLISH_STATE_DIR": str(state_dir),
    }

    _, err, code = run_polish("i want add login", env_overrides=overrides)
    assert err == ""
    assert code == 0

    log = state_dir / "debug.log"
    assert log.exists()
    body = log.read_text()
    assert "engine-error" in body
    assert "anthropic" in body

    size_after_first = log.stat().st_size
    run_polish("i want add login", env_overrides=overrides)
    assert log.stat().st_size == size_after_first


def test_debug_logs_skip_reason_when_enabled(tmp_path):
    state_dir = tmp_path / "state"
    overrides = {
        "POLISH_DEBUG": "1",
        "POLISH_STATE_DIR": str(state_dir),
        "POLISH_TEST_NO_ENGINE": "1",
    }

    run_polish("/help", env_overrides=overrides)

    log = state_dir / "debug.log"
    assert log.exists()
    assert "skip" in log.read_text()


def test_migrates_state_files_from_old_path(tmp_path):
    old_dir = tmp_path / "old"
    new_dir = tmp_path / "new"
    old_dir.mkdir()
    (old_dir / "debug.log").write_text("old log line\n")

    fake = _fake_response({"i want add login": "I want to add a login."})
    overrides = {
        **fake,
        "POLISH_STATE_DIR": str(new_dir),
        "POLISH_OLD_STATE_DIR": str(old_dir),
    }

    run_polish("i want add login", env_overrides=overrides)

    assert "old log line" in (new_dir / "debug.log").read_text()
    assert not (old_dir / "debug.log").exists()


def test_migration_is_idempotent_when_old_path_empty(tmp_path):
    old_dir = tmp_path / "old"  # never created
    new_dir = tmp_path / "new"

    fake = _fake_response({"i want add login": "I want to add a login."})
    overrides = {
        **fake,
        "POLISH_STATE_DIR": str(new_dir),
        "POLISH_OLD_STATE_DIR": str(old_dir),
    }

    _, _, code = run_polish("i want add login", env_overrides=overrides)
    assert code == 0


def test_debug_silent_when_disabled(tmp_path):
    state_dir = tmp_path / "state"
    overrides = {
        "POLISH_STATE_DIR": str(state_dir),
        "POLISH_TEST_NO_ENGINE": "1",
    }

    run_polish("/help", env_overrides=overrides)

    assert not (state_dir / "debug.log").exists()


# ---------- Hook protocol (JSON-on-stdin) mode ----------


def _hook_payload(prompt: str, **overrides) -> str:
    payload = {
        "session_id": "test-session",
        "transcript_path": "/tmp/x.jsonl",
        "cwd": "/tmp",
        "permission_mode": "default",
        "hook_event_name": "UserPromptSubmit",
        "prompt": prompt,
    }
    payload.update(overrides)
    return json.dumps(payload)


def test_hook_protocol_changed_text_emits_systemMessage_json():
    fake = _fake_response({"i want add login": "I want to add a login."})
    out, err, code = run_polish(_hook_payload("i want add login"), env_overrides=fake)
    assert code == 0
    # stderr is mirrored so terminals that don't render systemMessage still show it.
    assert "[polish] I want to add a login." in err
    response = json.loads(out)
    assert "[polish] I want to add a login." in response["systemMessage"]
    # Without POLISH_REPLACE, no additionalContext is injected.
    assert "hookSpecificOutput" not in response


def test_hook_protocol_unchanged_text_emits_empty_stdout():
    fake = _fake_response({"Read the auth file.": "Read the auth file."})
    out, err, code = run_polish(_hook_payload("Read the auth file."), env_overrides=fake)
    assert code == 0
    assert out == ""
    assert err == ""


def test_hook_protocol_skip_on_slash_command():
    # JSON payload carrying a slash command should produce empty stdout
    # (the prompt is skipped so no systemMessage is emitted).
    out, err, code = run_polish(_hook_payload("/help"))
    assert code == 0
    assert out == ""
    assert err == ""


def test_hook_protocol_replace_mode_adds_additionalContext():
    fake = _fake_response({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_REPLACE": "1"}
    out, _, code = run_polish(_hook_payload("i want add login"), env_overrides=overrides)
    assert code == 0
    response = json.loads(out)
    assert response["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit"
    assert "I want to add a login." in response["hookSpecificOutput"]["additionalContext"]


def test_hook_protocol_engine_failure_falls_through_silently():
    overrides = {"POLISH_TEST_FAKE_RESPONSE": "RAISE", "POLISH_TEST_NO_ENGINE": ""}
    out, err, code = run_polish(_hook_payload("i want add login"), env_overrides=overrides)
    assert code == 0
    assert out == ""
    assert err == ""


def test_hook_protocol_ignores_unknown_event_name():
    # Other hook events (PreToolUse, etc.) should fall through to legacy mode,
    # which then sees the JSON as raw text — multi-line, so it skips and echoes.
    payload = _hook_payload("hello", hook_event_name="PreToolUse")
    out, _, code = run_polish(payload)
    assert code == 0
    # Legacy mode echoes the raw input back to stdout when skipped.
    assert out == payload
