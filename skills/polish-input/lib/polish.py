#!/usr/bin/env python3
from __future__ import annotations
"""polish-input runtime: invoked as a Claude Code UserPromptSubmit hook.

Reads the prompt on stdin, applies skip rules, runs LanguageTool, and writes:
- stdout: the prompt Claude will see (original by default, polished if POLISH_REPLACE=1)
- stderr: a [polish] line for the user when the text changed

Always exits 0. Failures fall through silently so the user's prompt is never blocked.
"""
import json
import os
import sys

MAX_LEN = 4000


def should_skip(text: str) -> bool:
    if os.environ.get("POLISH_DISABLE") == "1":
        return True
    if not text:
        return True
    if text.startswith("/"):
        return True
    if "\n" in text:
        return True
    if len(text) > MAX_LEN:
        return True
    return False


def _correct(text: str) -> str | None:
    """Return corrected text, or None on any failure (fail open)."""
    fake = os.environ.get("POLISH_TEST_FAKE_LT")
    if fake is not None:
        if fake == "RAISE":
            raise RuntimeError("simulated LT failure")
        try:
            return json.loads(fake).get(text, text)
        except (json.JSONDecodeError, AttributeError):
            return None

    try:
        import language_tool_python  # local import: avoid cost when skipping
    except ImportError:
        return None
    try:
        tool = _get_tool(language_tool_python)
        return tool.correct(text)
    except Exception:
        return None


_TOOL = None


def _get_tool(language_tool_python):
    global _TOOL
    if _TOOL is None:
        _TOOL = language_tool_python.LanguageTool("en-US")
    return _TOOL


def _emit_polish_line(corrected: str) -> None:
    sys.stderr.write(f"[polish] {corrected}\n")
    sys.stderr.flush()


def main() -> int:
    text = sys.stdin.read()

    if should_skip(text):
        sys.stdout.write(text)
        return 0

    if os.environ.get("POLISH_TEST_NO_LT") == "1":
        sys.stdout.write(text)
        return 0

    try:
        corrected = _correct(text)
    except Exception:
        sys.stdout.write(text)
        return 0

    if corrected is None or corrected == text:
        sys.stdout.write(text)
        return 0

    _emit_polish_line(corrected)

    if os.environ.get("POLISH_REPLACE") == "1":
        sys.stdout.write(corrected)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
