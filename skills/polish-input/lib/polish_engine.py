#!/usr/bin/env python3
"""LLM-backed polish engine.

Uses the Anthropic Python SDK to rewrite a single-line prompt as natural,
native-sounding English. Returns None on any failure so the caller can fall
back to passing the original text through (fail open).

Reads ANTHROPIC_API_KEY and ANTHROPIC_BASE_URL from the environment via the
SDK's defaults — in Kiro mode these point at the Kiro gateway, so no second
key is required.
"""
from __future__ import annotations

import datetime
import os
from pathlib import Path

SYSTEM_PROMPT = (
    "Rewrite the user's message as natural, native-sounding English. "
    "Preserve technical terms, code, file paths, URLs, command-line flags, "
    "and the original meaning exactly. Do not answer the message. Do not "
    "add commentary. Output only the rewritten text. If the input is "
    "already fluent, return it unchanged."
)

DEFAULT_MODEL = "claude-haiku-4-5"
DEFAULT_TIMEOUT_MS = 3000
DEFAULT_MAX_TOKENS = 1500

DEFAULT_STATE_DIR = "~/.claude/state/polish-input"


def _state_dir() -> Path:
    raw = os.environ.get("POLISH_STATE_DIR") or DEFAULT_STATE_DIR
    path = Path(os.path.expanduser(raw))
    path.mkdir(parents=True, exist_ok=True)
    return path


def _write_engine_error_hint_once(reason: str) -> None:
    marker = _state_dir() / ".engine-error"
    if marker.exists():
        return
    hint = (
        f"engine-error: {reason}\n"
        "polish-input could not call the polish engine.\n"
        "Make sure `anthropic` is installed (`pip install --user anthropic`) "
        "and that ANTHROPIC_API_KEY is set in the environment Claude Code "
        "runs in.\n"
    )
    try:
        with (_state_dir() / "debug.log").open("a") as f:
            ts = datetime.datetime.now(datetime.timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            )
            f.write(f"[{ts}] {hint}")
        marker.touch()
    except OSError:
        pass


def polish(text: str) -> str | None:
    """Return rewritten text, or None on any failure (fail open)."""
    try:
        import anthropic
    except ImportError as e:
        _write_engine_error_hint_once(f"anthropic SDK not importable: {e}")
        return None

    try:
        timeout_s = int(os.environ.get("POLISH_TIMEOUT_MS", str(DEFAULT_TIMEOUT_MS))) / 1000
        client = anthropic.Anthropic()
        resp = client.messages.create(
            model=os.environ.get("POLISH_MODEL", DEFAULT_MODEL),
            max_tokens=DEFAULT_MAX_TOKENS,
            timeout=timeout_s,
            system=[
                {
                    "type": "text",
                    "text": SYSTEM_PROMPT,
                    "cache_control": {"type": "ephemeral"},
                }
            ],
            messages=[{"role": "user", "content": text}],
        )
        return resp.content[0].text.strip()
    except Exception as e:
        _write_engine_error_hint_once(f"Anthropic API call failed: {e}")
        return None
