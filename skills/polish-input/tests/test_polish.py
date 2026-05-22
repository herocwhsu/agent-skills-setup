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
    # Default: ensure tests don't accidentally hit a real LT install.
    env["POLISH_TEST_NO_LT"] = "1"
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


def _fake_lt(mapping: dict[str, str]) -> dict[str, str]:
    """Return env overrides that inject a fake LT correction map."""
    return {"POLISH_TEST_FAKE_LT": json.dumps(mapping), "POLISH_TEST_NO_LT": ""}


def test_changed_text_emits_stderr_and_keeps_stdout_original():
    fake = _fake_lt({"i want add login": "I want to add a login."})
    out, err, code = run_polish("i want add login", env_overrides=fake)
    assert out == "i want add login"
    assert "[polish]" in err
    assert "I want to add a login." in err
    assert code == 0


def test_unchanged_text_emits_no_stderr():
    fake = _fake_lt({"Read the auth file.": "Read the auth file."})
    out, err, code = run_polish("Read the auth file.", env_overrides=fake)
    assert out == "Read the auth file."
    assert err == ""
    assert code == 0


def test_replace_mode_sends_polished_to_stdout():
    fake = _fake_lt({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_REPLACE": "1"}
    out, err, code = run_polish("i want add login", env_overrides=overrides)
    assert out == "I want to add a login."
    assert "[polish]" in err
    assert code == 0


def test_lt_error_fails_open():
    overrides = {"POLISH_TEST_FAKE_LT": "RAISE", "POLISH_TEST_NO_LT": ""}
    out, err, code = run_polish("i want add login", env_overrides=overrides)
    assert out == "i want add login"
    assert err == ""
    assert code == 0


def test_display_line_default():
    fake = _fake_lt({"i want add login": "I want to add a login."})
    _, err, _ = run_polish("i want add login", env_overrides=fake)
    assert err == "[polish] I want to add a login.\n"


def test_display_diff_shows_word_changes():
    fake = _fake_lt({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_DISPLAY": "diff"}
    _, err, _ = run_polish("i want add login", env_overrides=overrides)
    assert err.startswith("[polish] ")
    # Diff format must show added "to" and "a" or removed "i" somehow.
    assert "+" in err or "-" in err


def test_display_box_wraps_in_borders():
    fake = _fake_lt({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_DISPLAY": "box"}
    _, err, _ = run_polish("i want add login", env_overrides=overrides)
    # Box must contain some border character on lines and the polished text.
    assert "I want to add a login." in err
    lines = err.strip().split("\n")
    assert len(lines) >= 3  # top border, content, bottom border


def test_display_invalid_falls_back_to_line():
    fake = _fake_lt({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_DISPLAY": "nonsense"}
    _, err, _ = run_polish("i want add login", env_overrides=overrides)
    assert err == "[polish] I want to add a login.\n"
