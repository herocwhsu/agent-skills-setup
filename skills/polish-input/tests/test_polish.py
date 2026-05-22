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
