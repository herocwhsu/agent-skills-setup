#!/usr/bin/env python3
from __future__ import annotations
"""polish-input runtime: invoked as a Claude Code UserPromptSubmit hook.

Two stdin modes are supported:

1. Hook-protocol mode (current Claude Code): stdin is a JSON object with
   `hook_event_name == "UserPromptSubmit"` and a `prompt` field. We emit a
   JSON response on stdout containing `systemMessage` (user-visible) and,
   when POLISH_REPLACE=1, `hookSpecificOutput.additionalContext` so the
   model also sees the polished version. Plain stdout is NOT used here —
   the docs say plain stdout becomes additional context, which would
   duplicate the prompt.

2. Legacy raw-text mode (used by tests and direct piping): stdin is the
   prompt as plain text. We write the original (or polished, if
   POLISH_REPLACE=1) to stdout and emit `[polish] ...` on stderr.

Always exits 0. Failures fall through silently so the user's prompt is never blocked.
"""
import datetime
import difflib
import json
import os
import sys
from pathlib import Path

MAX_LEN = 4000


DEFAULT_STATE_DIR = "~/.claude/state/polish-input"
LEGACY_STATE_DIR = "~/.claude/skills/polish-input"
_MIGRATED = False


def _migrate_legacy_state(new_dir: Path) -> None:
    """One-shot best-effort migration from the legacy state path."""
    global _MIGRATED
    if _MIGRATED:
        return
    _MIGRATED = True
    legacy_raw = os.environ.get("POLISH_OLD_STATE_DIR") or LEGACY_STATE_DIR
    legacy = Path(os.path.expanduser(legacy_raw))
    if legacy.resolve() == new_dir.resolve():
        return
    if not legacy.is_dir():
        return
    for name in (".initialized", ".lt-error", "debug.log"):
        src = legacy / name
        if not src.is_file():
            continue
        dst = new_dir / name
        try:
            if name == "debug.log" and dst.exists():
                dst.write_text(dst.read_text() + src.read_text())
            else:
                src.replace(dst)
            try:
                src.unlink()
            except FileNotFoundError:
                pass
        except OSError:
            pass


def _state_dir() -> Path:
    # POLISH_STATE_DIR overrides the default location; primarily used by tests.
    raw = os.environ.get("POLISH_STATE_DIR") or DEFAULT_STATE_DIR
    path = Path(os.path.expanduser(raw))
    path.mkdir(parents=True, exist_ok=True)
    _migrate_legacy_state(path)
    return path


def _debug_log(event: str, detail: str = "") -> None:
    if os.environ.get("POLISH_DEBUG") != "1":
        return
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    line = f"[{ts}] {event}: {detail}\n" if detail else f"[{ts}] {event}\n"
    try:
        with (_state_dir() / "debug.log").open("a") as f:
            f.write(line)
    except OSError:
        pass


def _write_lt_error_hint_once(reason: str) -> None:
    marker = _state_dir() / ".lt-error"
    if marker.exists():
        return
    hint = (
        f"lt-error: {reason}\n"
        "polish-input could not run LanguageTool. Most likely cause: Java is missing.\n"
        "Install OpenJDK (macOS: `brew install openjdk@17`; Linux: `sudo apt-get install default-jre`)\n"
        "and ensure `language_tool_python` is installed: `pip install --user language_tool_python`.\n"
    )
    try:
        with (_state_dir() / "debug.log").open("a") as f:
            f.write(hint)
        marker.touch()
    except OSError:
        pass


def _skip_reason(text: str) -> str | None:
    """Return skip reason if text should be skipped, None otherwise."""
    if os.environ.get("POLISH_DISABLE") == "1":
        return "POLISH_DISABLE=1"
    if not text:
        return "empty input"
    if text.startswith("/"):
        return "slash command"
    if "\n" in text:
        return "multi-line"
    if len(text) > MAX_LEN:
        return f"over MAX_LEN ({len(text)} > {MAX_LEN})"
    return None


def should_skip(text: str) -> bool:
    return _skip_reason(text) is not None


def _correct(text: str) -> str | None:
    """Return corrected text, or None on any failure (fail open)."""
    fake = os.environ.get("POLISH_TEST_FAKE_LT")
    if fake is not None:
        if fake == "RAISE":
            _write_lt_error_hint_once("simulated LT failure")
            raise RuntimeError("simulated LT failure")
        try:
            mapping = json.loads(fake)
        except (json.JSONDecodeError, AttributeError):
            return None
        # Honor first-run message even in test mode so we can verify the path.
        _maybe_show_first_run_message()
        return mapping.get(text, text)

    try:
        import language_tool_python  # local import: avoid cost when skipping
    except ImportError as e:
        _write_lt_error_hint_once(f"language_tool_python import failed: {e}")
        return None
    try:
        tool = _get_tool(language_tool_python)
        return tool.correct(text)
    except Exception as e:
        _write_lt_error_hint_once(f"LanguageTool call failed: {e}")
        return None


_TOOL = None


def _maybe_show_first_run_message() -> None:
    marker = _state_dir() / ".initialized"
    if marker.exists():
        return
    sys.stderr.write("[polish] initializing LanguageTool, this happens once...\n")
    sys.stderr.flush()
    try:
        marker.touch()
    except OSError:
        pass


def _get_tool(language_tool_python):
    global _TOOL
    if _TOOL is None:
        _maybe_show_first_run_message()
        _TOOL = language_tool_python.LanguageTool("en-US")
    return _TOOL


def _format_line(corrected: str, _original: str) -> str:
    return f"[polish] {corrected}\n"


def _format_diff(corrected: str, original: str) -> str:
    orig_words = original.split()
    new_words = corrected.split()
    matcher = difflib.SequenceMatcher(a=orig_words, b=new_words)
    parts = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            parts.extend(orig_words[i1:i2])
        elif tag == "delete":
            parts.extend(f"-{w}" for w in orig_words[i1:i2])
        elif tag == "insert":
            parts.extend(f"+{w}" for w in new_words[j1:j2])
        elif tag == "replace":
            parts.extend(f"-{w}" for w in orig_words[i1:i2])
            parts.extend(f"+{w}" for w in new_words[j1:j2])
    return f"[polish] {' '.join(parts)}\n"


def _format_box(corrected: str, _original: str) -> str:
    line = f"  {corrected}  "
    border = "─" * len(line)
    return f"┌{border}┐\n│{line}│\n└{border}┘\n"


_FORMATTERS = {
    "line": _format_line,
    "diff": _format_diff,
    "box": _format_box,
}


def _emit_polish_line(corrected: str, original: str) -> None:
    style = os.environ.get("POLISH_DISPLAY", "line")
    formatter = _FORMATTERS.get(style, _format_line)
    sys.stderr.write(formatter(corrected, original))
    sys.stderr.flush()


def _parse_hook_payload(raw: str) -> dict | None:
    """Detect the Claude Code hook JSON payload. Returns the parsed dict
    when it looks like a UserPromptSubmit event, else None."""
    stripped = raw.lstrip()
    if not stripped.startswith("{"):
        return None
    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    if payload.get("hook_event_name") != "UserPromptSubmit":
        return None
    if not isinstance(payload.get("prompt"), str):
        return None
    return payload


def _polish_text(text: str) -> tuple[str | None, str]:
    """Apply skip rules + LanguageTool. Returns (corrected_or_None, reason).

    `corrected` is None when the text was skipped, LT failed, or the result
    matched the input. `reason` is a short label for debug logging."""
    skip = _skip_reason(text)
    if skip is not None:
        return None, f"skip:{skip}"

    if os.environ.get("POLISH_TEST_NO_LT") == "1":
        return None, "test-no-lt"

    try:
        corrected = _correct(text)
    except Exception as e:
        _debug_log("correct-failed", str(e))
        return None, "correct-failed"

    if corrected is None or corrected == text:
        return None, "no-change"
    return corrected, "polished"


def _run_hook_protocol(payload: dict) -> int:
    prompt = payload["prompt"]
    corrected, reason = _polish_text(prompt)

    if corrected is None:
        _debug_log(reason.split(":", 1)[0], reason.split(":", 1)[1] if ":" in reason else "")
        # Empty stdout = no additional context injected.
        return 0

    _debug_log("polished", corrected)

    style = os.environ.get("POLISH_DISPLAY", "line")
    formatter = _FORMATTERS.get(style, _format_line)
    # Strip the trailing newline from formatters; systemMessage renders it as one line.
    system_message = formatter(corrected, prompt).rstrip("\n")

    response: dict = {"systemMessage": system_message}
    if os.environ.get("POLISH_REPLACE") == "1":
        response["hookSpecificOutput"] = {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": f"User's prompt polished to: {corrected}",
        }
    sys.stdout.write(json.dumps(response))
    return 0


def _run_legacy_text(text: str) -> int:
    if should_skip(text):
        _debug_log("skip", _skip_reason(text))
        sys.stdout.write(text)
        return 0

    if os.environ.get("POLISH_TEST_NO_LT") == "1":
        sys.stdout.write(text)
        return 0

    try:
        corrected = _correct(text)
    except Exception as e:
        _debug_log("correct-failed", str(e))
        sys.stdout.write(text)
        return 0

    if corrected is None or corrected == text:
        _debug_log("no-change", "")
        sys.stdout.write(text)
        return 0

    _debug_log("polished", corrected)
    _emit_polish_line(corrected, text)

    if os.environ.get("POLISH_REPLACE") == "1":
        sys.stdout.write(corrected)
    else:
        sys.stdout.write(text)
    return 0


def main() -> int:
    raw = sys.stdin.read()

    payload = _parse_hook_payload(raw)
    if payload is not None:
        return _run_hook_protocol(payload)

    # Legacy raw-text mode: strip a single trailing newline (common when
    # invoked via `echo "..." |`). Real multi-line input still has internal
    # \n which is caught by the skip rule.
    text = raw[:-1] if raw.endswith("\n") else raw
    return _run_legacy_text(text)


if __name__ == "__main__":
    sys.exit(main())
