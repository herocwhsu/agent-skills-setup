#!/usr/bin/env python3
"""polish-input runtime: invoked as a Claude Code UserPromptSubmit hook.

Reads the prompt on stdin, applies skip rules, runs LanguageTool, and writes:
- stdout: the prompt Claude will see (original by default, polished if POLISH_REPLACE=1)
- stderr: a [polish] line for the user when the text changed

Always exits 0. Failures fall through silently so the user's prompt is never blocked.
"""
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


def main() -> int:
    text = sys.stdin.read()

    if should_skip(text):
        sys.stdout.write(text)
        return 0

    # Test hatch: skip LT entirely so unit tests don't need Java.
    if os.environ.get("POLISH_TEST_NO_LT") == "1":
        sys.stdout.write(text)
        return 0

    # LT integration lands in Task 4.
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
