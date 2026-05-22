# polish-input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `polish-input` skill that auto-polishes English prompts via a Claude Code `UserPromptSubmit` hook, using local LanguageTool. Default behavior shows the polish on stderr without changing what Claude receives.

**Architecture:** The skill ships four files (`SKILL.md`, `README.md`, `hook.json`, `lib/polish.py`). The actual runtime is `lib/polish.py`, invoked by Claude Code's `UserPromptSubmit` hook. Distribution rides the existing `registry.txt` + `scripts/install.sh` patterns; an opt-in `--with-hook polish-input` flag handles Java/pip prerequisites and merges the hook into `~/.claude/settings.json` via a new `scripts/_settings_merge.py` helper.

**Tech Stack:** Python 3.8+, `language_tool_python` (which downloads LanguageTool JAR + requires JRE), bash, `jq` (with Python fallback).

**Spec:** `docs/superpowers/specs/2026-05-22-polish-input-design.md`

---

## File Structure

Files this plan creates or modifies:

| Path | Action | Responsibility |
|---|---|---|
| `skills/polish-input/SKILL.md` | Create | agentskills.io metadata. The skill is hook-driven; SKILL.md exists for discoverability. |
| `skills/polish-input/README.md` | Create | Human docs: install, configure, troubleshoot. |
| `skills/polish-input/hook.json` | Create | Snippet merged into `~/.claude/settings.json` by install.sh. |
| `skills/polish-input/lib/polish.py` | Create | Runtime. Reads stdin, applies skip rules + LT, writes stdout/stderr per spec. |
| `skills/polish-input/tests/test_polish.py` | Create | pytest unit tests; mocks LanguageTool. |
| `skills/polish-input/tests/integration_polish.sh` | Create | End-to-end smoke test; gated on Java availability. |
| `scripts/_settings_merge.py` | Create | jq-fallback helper that merges hook.json into settings.json. |
| `scripts/install.sh` | Modify | Add `--with-hook <skill>` flag. |
| `scripts/uninstall.sh` | Modify | Add `--with-hook <skill>` flag (un-wires hook). |
| `registry.txt` | Modify | Add `local polish-input`. |

---

## Task 1: Scaffold Skill Directory and Metadata Files

**Files:**
- Create: `skills/polish-input/SKILL.md`
- Create: `skills/polish-input/README.md`
- Create: `skills/polish-input/hook.json`

- [ ] **Step 1: Create the skill directory and SKILL.md**

```bash
mkdir -p skills/polish-input/lib skills/polish-input/tests
```

Write `skills/polish-input/SKILL.md`:

```markdown
---
name: polish-input
description: Use when the user wants automatic English polish on every prompt. Installs a Claude Code UserPromptSubmit hook that runs LanguageTool on each single-line prompt and shows the polished version on stderr. Default behavior does not change what Claude receives.
---

# polish-input

This skill installs a runtime hook for Claude Code. It does not require the agent to take action — once installed, every single-line, non-slash-command prompt the user types is run through LanguageTool, and the polished version is printed to the user's terminal as a learning side-channel.

See `README.md` for installation, configuration, and troubleshooting.
```

- [ ] **Step 2: Create the hook JSON snippet**

Write `skills/polish-input/hook.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "command": "python3 ~/.claude/skills/polish-input/lib/polish.py"
      }
    ]
  }
}
```

- [ ] **Step 3: Create the README skeleton**

Write `skills/polish-input/README.md`:

```markdown
# polish-input

Auto-polish single-line English prompts as a learning side-channel for Claude Code.

## What it does

```
you> i want add new feature for login
[polish] I want to add a new feature for login.
claude> Sure — let's start by looking at the auth code…
```

Claude receives the original prompt by default. The polish line is purely informational.

## Install

```bash
bash scripts/install.sh --with-hook polish-input
```

This:
1. Installs the skill files (symlinks `skills/polish-input/` → `~/.claude/skills/polish-input/`).
2. Checks for a Java runtime; offers to install OpenJDK via brew (macOS) or apt (Linux) if missing.
3. Installs `language_tool_python` via pip.
4. Merges the `UserPromptSubmit` hook into `~/.claude/settings.json`.

The first prompt after install downloads the LanguageTool JAR (~200MB) and shows `[polish] initializing LanguageTool, this happens once…`.

## Configuration

All env vars are optional.

| Var | Default | Effect |
|---|---|---|
| `POLISH_DISABLE` | unset | If `1`, hook is a no-op. Instant escape hatch. |
| `POLISH_REPLACE` | unset | If `1`, send the polished text to Claude instead of the original. |
| `POLISH_DISPLAY` | `line` | `line` / `diff` / `box`. |
| `POLISH_DEBUG` | unset | If `1`, log diagnostics to `~/.claude/skills/polish-input/debug.log`. |

Set them in `~/.claude/settings.json` under `env`, or in your shell rc.

## Skip rules

The hook is silent when:
- The prompt starts with `/` (slash command).
- The prompt contains a newline (multi-line).
- The prompt is over 4000 characters.
- `POLISH_DISABLE=1` is set.
- LanguageTool is unavailable (fail open).

## Uninstall

```bash
bash scripts/uninstall.sh --with-hook polish-input
```

Removes the hook entry and unlinks the skill. Java and the pip package are left in place; remove manually if desired.

## Troubleshooting

- **No polish appears on imperfect prompts:** Check `~/.claude/skills/polish-input/debug.log`. Most likely cause: Java is missing.
- **First prompt hangs for 30+ seconds:** Expected. LanguageTool is downloading on first use; this only happens once.
- **Windows:** Auto-wiring is not implemented. Install the skill files normally, then manually add the hook from `hook.json` to `%USERPROFILE%\.claude\settings.json`.
```

- [ ] **Step 4: Verify files are well-formed**

Run:
```bash
python3 -c "import json; json.load(open('skills/polish-input/hook.json'))"
ls -la skills/polish-input/
```

Expected: no JSON error; the directory contains `SKILL.md`, `README.md`, `hook.json`, `lib/`, `tests/`.

- [ ] **Step 5: Commit**

```bash
git add skills/polish-input/
git commit -m "feat(polish-input): scaffold skill directory and metadata"
```

---

## Task 2: Add Registry Entry

**Files:**
- Modify: `registry.txt`

- [ ] **Step 1: Append the registry line**

Append a single line to `registry.txt`:

```
local  polish-input
```

The final file should have `local  polish-input` as the last non-blank line, after the existing `local  create-story-tasks` entry.

- [ ] **Step 2: Verify the registry parses**

Run:
```bash
grep -E "^local\s+polish-input$" registry.txt
```

Expected: prints the matching line.

- [ ] **Step 3: Commit**

```bash
git add registry.txt
git commit -m "feat(polish-input): register skill in registry.txt"
```

---

## Task 3: Polish Runtime — Skip Rules (TDD)

**Files:**
- Create: `skills/polish-input/tests/test_polish.py`
- Create: `skills/polish-input/lib/polish.py`

This task implements only the skip-rule logic. LanguageTool integration arrives in Task 4. Skip rules: slash command, multi-line, over-length, `POLISH_DISABLE=1`. When a skip rule applies, `polish.py` writes stdin verbatim to stdout and exits 0 with empty stderr — without ever touching LanguageTool.

- [ ] **Step 1: Write the failing tests for skip rules**

Write `skills/polish-input/tests/test_polish.py`:

```python
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd skills/polish-input && python3 -m pytest tests/test_polish.py -v
```

Expected: FAIL — `polish.py` does not exist.

- [ ] **Step 3: Implement polish.py with skip rules only**

Write `skills/polish-input/lib/polish.py`:

```python
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
```

Make it executable:
```bash
chmod +x skills/polish-input/lib/polish.py
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
cd skills/polish-input && python3 -m pytest tests/test_polish.py -v
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add skills/polish-input/lib/polish.py skills/polish-input/tests/test_polish.py
git commit -m "feat(polish-input): runtime skip rules + tests"
```

---

## Task 4: Polish Runtime — LanguageTool Integration (TDD)

**Files:**
- Modify: `skills/polish-input/lib/polish.py`
- Modify: `skills/polish-input/tests/test_polish.py`

LanguageTool runs through `language_tool_python.LanguageTool('en-US').correct(text)`. We can't install Java in CI, so the unit test injects a fake by setting `POLISH_TEST_FAKE_LT` to a JSON map of `original → corrected`. Production code path only kicks in when neither `POLISH_TEST_NO_LT` nor `POLISH_TEST_FAKE_LT` is set.

- [ ] **Step 1: Add tests for the fake-LT injection path**

Append to `skills/polish-input/tests/test_polish.py`:

```python
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
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:
```bash
cd skills/polish-input && python3 -m pytest tests/test_polish.py -v
```

Expected: 4 new tests FAIL (existing 5 still PASS).

- [ ] **Step 3: Implement LT integration in polish.py**

Replace the body of `main()` in `skills/polish-input/lib/polish.py` with:

```python
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
```

Add `import json` at the top of the file (next to `import os`).

- [ ] **Step 4: Run all tests to verify pass**

Run:
```bash
cd skills/polish-input && python3 -m pytest tests/test_polish.py -v
```

Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
git add skills/polish-input/lib/polish.py skills/polish-input/tests/test_polish.py
git commit -m "feat(polish-input): LanguageTool integration with fail-open"
```

---

## Task 5: Display Format Variants (TDD)

**Files:**
- Modify: `skills/polish-input/lib/polish.py`
- Modify: `skills/polish-input/tests/test_polish.py`

`POLISH_DISPLAY` chooses the stderr format: `line` (default), `diff` (word-level diff), or `box` (boxed block). Diff uses Python's stdlib `difflib` for word tokens.

- [ ] **Step 1: Add tests for each display format**

Append to `skills/polish-input/tests/test_polish.py`:

```python
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
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:
```bash
cd skills/polish-input && python3 -m pytest tests/test_polish.py -v -k display
```

Expected: 4 FAIL (only `display_line_default` may pass since current default is line-style).

- [ ] **Step 3: Implement display variants**

Replace `_emit_polish_line` in `skills/polish-input/lib/polish.py` with:

```python
import difflib  # add near other imports


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
```

Update the call site in `main()` from `_emit_polish_line(corrected)` to `_emit_polish_line(corrected, text)`.

- [ ] **Step 4: Run all tests to verify pass**

Run:
```bash
cd skills/polish-input && python3 -m pytest tests/test_polish.py -v
```

Expected: 13 passed.

- [ ] **Step 5: Commit**

```bash
git add skills/polish-input/lib/polish.py skills/polish-input/tests/test_polish.py
git commit -m "feat(polish-input): display format variants (line, diff, box)"
```

---

## Task 6: First-Run Message, Error Marker, and Debug Logging (TDD)

**Files:**
- Modify: `skills/polish-input/lib/polish.py`
- Modify: `skills/polish-input/tests/test_polish.py`

Three behaviors required by the spec but not yet implemented:

1. **First-run init message** — the very first time `_correct()` constructs a real `LanguageTool`, the user sees `[polish] initializing LanguageTool, this happens once...` on stderr. A marker file `~/.claude/skills/polish-input/.initialized` suppresses the message thereafter.
2. **First-error hint** — when `_correct()` fails (Java missing, import error, runtime exception), append a one-time setup hint to `debug.log`. A marker file `~/.claude/skills/polish-input/.lt-error` suppresses repeats.
3. **POLISH_DEBUG=1** — when set, log `[YYYY-MM-DDTHH:MM:SSZ] <event>: <detail>` lines to `debug.log` for observability (skip decisions, LT timing, etc.).

The marker directory is configurable via `POLISH_STATE_DIR` so tests can use a tmp path.

- [ ] **Step 1: Write the failing tests**

Append to `skills/polish-input/tests/test_polish.py`:

```python
def test_first_run_message_then_suppressed(tmp_path):
    state_dir = tmp_path / "state"
    fake = _fake_lt({"i want add login": "I want to add a login."})
    overrides = {**fake, "POLISH_STATE_DIR": str(state_dir)}

    _, err1, _ = run_polish("i want add login", env_overrides=overrides)
    assert "initializing LanguageTool" in err1
    assert (state_dir / ".initialized").exists()

    _, err2, _ = run_polish("i want add login", env_overrides=overrides)
    assert "initializing LanguageTool" not in err2


def test_lt_error_writes_one_time_hint_to_debug_log(tmp_path):
    state_dir = tmp_path / "state"
    overrides = {
        "POLISH_TEST_FAKE_LT": "RAISE",
        "POLISH_TEST_NO_LT": "",
        "POLISH_STATE_DIR": str(state_dir),
    }

    _, err, code = run_polish("i want add login", env_overrides=overrides)
    assert err == ""
    assert code == 0

    log = state_dir / "debug.log"
    assert log.exists()
    body = log.read_text()
    assert "lt-error" in body
    assert "Java" in body or "language_tool_python" in body

    size_after_first = log.stat().st_size
    run_polish("i want add login", env_overrides=overrides)
    assert log.stat().st_size == size_after_first


def test_debug_logs_skip_reason_when_enabled(tmp_path):
    state_dir = tmp_path / "state"
    overrides = {
        "POLISH_DEBUG": "1",
        "POLISH_STATE_DIR": str(state_dir),
        "POLISH_TEST_NO_LT": "1",
    }

    run_polish("/help", env_overrides=overrides)

    log = state_dir / "debug.log"
    assert log.exists()
    assert "skip" in log.read_text()


def test_debug_silent_when_disabled(tmp_path):
    state_dir = tmp_path / "state"
    overrides = {
        "POLISH_STATE_DIR": str(state_dir),
        "POLISH_TEST_NO_LT": "1",
    }

    run_polish("/help", env_overrides=overrides)

    assert not (state_dir / "debug.log").exists()
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:
```bash
cd skills/polish-input && python3 -m pytest tests/test_polish.py -v -k "first_run or lt_error or debug"
```

Expected: 4 FAIL.

- [ ] **Step 3: Implement state-directory helpers and debug logger**

Add near the top of `skills/polish-input/lib/polish.py` (next to existing imports):

```python
import datetime
from pathlib import Path
```

Add these helpers above `should_skip()`:

```python
def _state_dir() -> Path:
    raw = os.environ.get("POLISH_STATE_DIR") or "~/.claude/skills/polish-input"
    path = Path(os.path.expanduser(raw))
    path.mkdir(parents=True, exist_ok=True)
    return path


def _debug_log(event: str, detail: str = "") -> None:
    if os.environ.get("POLISH_DEBUG") != "1":
        return
    ts = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    line = f"[{ts}] {event}: {detail}\n" if detail else f"[{ts}] {event}\n"
    try:
        (_state_dir() / "debug.log").open("a").write(line)
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
        (_state_dir() / "debug.log").open("a").write(hint)
        marker.touch()
    except OSError:
        pass
```

- [ ] **Step 4: Wire the first-run message and error hint into `_correct()`**

Replace the existing `_correct()` and `_get_tool()` functions with:

```python
def _correct(text: str) -> str | None:
    fake = os.environ.get("POLISH_TEST_FAKE_LT")
    if fake is not None:
        if fake == "RAISE":
            _write_lt_error_hint_once("simulated LT failure")
            raise RuntimeError("simulated LT failure")
        try:
            mapping = json.loads(fake)
        except json.JSONDecodeError:
            return None
        # Honor first-run message even in test mode so we can verify the path.
        _maybe_show_first_run_message()
        return mapping.get(text, text)

    try:
        import language_tool_python
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
```

- [ ] **Step 5: Wire debug logging into `main()`**

Update `main()` so it logs key events when `POLISH_DEBUG=1`:

```python
def main() -> int:
    text = sys.stdin.read()

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
```

Add the `_skip_reason` helper next to `should_skip`:

```python
def _skip_reason(text: str) -> str:
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
    return "unknown"
```

- [ ] **Step 6: Run all tests to verify pass**

Run:
```bash
cd skills/polish-input && python3 -m pytest tests/test_polish.py -v
```

Expected: 17 passed (13 prior + 4 new).

- [ ] **Step 7: Commit**

```bash
git add skills/polish-input/lib/polish.py skills/polish-input/tests/test_polish.py
git commit -m "feat(polish-input): first-run init message, error marker, debug log"
```

---

## Task 7: Settings Merge Helper

**Files:**
- Create: `scripts/_settings_merge.py`
- Create: `tests/test_settings_merge.py`

The helper merges `hook.json` into `~/.claude/settings.json` without overwriting existing user hooks or other settings. It is idempotent — running it twice with the same hook produces the same file. It also supports `--remove` for un-wiring.

- [ ] **Step 1: Write the failing test**

Create the project-level tests directory if missing:
```bash
mkdir -p tests
```

Write `tests/test_settings_merge.py`:

```python
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
python3 -m pytest tests/test_settings_merge.py -v
```

Expected: FAIL — `_settings_merge.py` does not exist.

- [ ] **Step 3: Implement the helper**

Write `scripts/_settings_merge.py`:

```python
#!/usr/bin/env python3
"""Merge or remove a hook JSON snippet into ~/.claude/settings.json.

Usage:
    _settings_merge.py --merge  hook.json settings.json
    _settings_merge.py --remove hook.json settings.json

Operates only on top-level "hooks.<EventName>" arrays. Preserves all other keys
and other event names. Idempotent. Creates settings.json if missing on --merge.
"""
import argparse
import json
import sys
from pathlib import Path


def load_settings(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text() or "{}")
    except json.JSONDecodeError as e:
        print(f"error: {path} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)


def save_settings(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def merge(hook: dict, settings: dict) -> dict:
    settings.setdefault("hooks", {})
    for event, entries in hook.get("hooks", {}).items():
        existing = settings["hooks"].setdefault(event, [])
        existing_cmds = {h.get("command") for h in existing}
        for entry in entries:
            if entry.get("command") not in existing_cmds:
                existing.append(entry)
    return settings


def remove(hook: dict, settings: dict) -> dict:
    if "hooks" not in settings:
        return settings
    for event, entries in hook.get("hooks", {}).items():
        if event not in settings["hooks"]:
            continue
        cmds_to_drop = {h.get("command") for h in entries}
        settings["hooks"][event] = [
            h for h in settings["hooks"][event] if h.get("command") not in cmds_to_drop
        ]
        if not settings["hooks"][event]:
            del settings["hooks"][event]
    if not settings["hooks"]:
        del settings["hooks"]
    return settings


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--merge", action="store_true")
    group.add_argument("--remove", action="store_true")
    parser.add_argument("hook_path", type=Path)
    parser.add_argument("settings_path", type=Path)
    args = parser.parse_args()

    hook = json.loads(args.hook_path.read_text())

    if args.remove and not args.settings_path.exists():
        return 0

    settings = load_settings(args.settings_path)
    if args.merge:
        settings = merge(hook, settings)
    else:
        settings = remove(hook, settings)

    save_settings(args.settings_path, settings)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Make it executable:
```bash
chmod +x scripts/_settings_merge.py
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
python3 -m pytest tests/test_settings_merge.py -v
```

Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/_settings_merge.py tests/test_settings_merge.py
git commit -m "feat: add _settings_merge.py helper for hook wiring"
```

---

## Task 8: install.sh — `--with-hook` Flag

**Files:**
- Modify: `scripts/install.sh`

This task adds the `--with-hook <skill>` flag. The flag is repeatable (`--with-hook a --with-hook b`). After the normal install loop, for each `--with-hook` value:
1. Verify the skill ships a `hook.json` (if not, error and exit).
2. Check `java -version`. If missing, prompt to install via brew (Darwin) or apt (Linux). On decline or unsupported OS, print a warning and continue.
3. `pip install --user --quiet language_tool_python` (only when the skill is `polish-input`; we keep this skill-specific to avoid forcing the dependency for hypothetical future hooks).
4. Run `_settings_merge.py --merge` against `~/.claude/settings.json`.

- [ ] **Step 1: Add the argument parsing**

Open `scripts/install.sh`. Replace the existing argument-parsing `while` loop (currently parsing only `--agent`) with:

```bash
AGENT_ARG=""
HOOK_SKILLS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      AGENT_ARG="$2"; shift 2 ;;
    --agent=*)
      AGENT_ARG="${1#*=}"; shift ;;
    --with-hook)
      HOOK_SKILLS+=("$2"); shift 2 ;;
    --with-hook=*)
      HOOK_SKILLS+=("${1#*=}"); shift ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
```

- [ ] **Step 2: Add the hook-wiring step at the end of install.sh**

Just before the final `echo "Done. ..."` line, insert:

```bash
if [[ ${#HOOK_SKILLS[@]} -gt 0 ]]; then
  echo ""
  echo "==> Wiring hooks..."
  for skill in "${HOOK_SKILLS[@]}"; do
    wire_hook "$skill" "$REPO_DIR"
  done
fi
```

- [ ] **Step 3: Add the `wire_hook` function to `_lib.sh`**

Append to `scripts/_lib.sh`:

```bash
# Install Java if missing, prompting the user. Returns 0 if Java is available
# afterward, 1 if not (caller should fail open).
ensure_java() {
  if command -v java &>/dev/null; then
    return 0
  fi

  case "$(detect_os)" in
    darwin)
      if command -v brew &>/dev/null; then
        echo "  Java not found. Install OpenJDK 17 via brew? [y/N]"
        read -r reply
        if [[ "$reply" =~ ^[Yy]$ ]]; then
          brew install openjdk@17 || return 1
          return 0
        fi
      else
        echo "  WARNING: Java not found and Homebrew not installed. Install OpenJDK manually." >&2
        return 1
      fi
      ;;
    linux-gui|linux-headless)
      if command -v apt-get &>/dev/null; then
        echo "  Java not found. Install default-jre via apt? [y/N]"
        read -r reply
        if [[ "$reply" =~ ^[Yy]$ ]]; then
          sudo apt-get install -y default-jre || return 1
          return 0
        fi
      else
        echo "  WARNING: Java not found and apt not available. Install a JRE manually." >&2
        return 1
      fi
      ;;
    *)
      echo "  WARNING: Java auto-install not supported on this OS. Install a JRE manually." >&2
      return 1
      ;;
  esac

  echo "  Skipping Java install. polish-input will fail open until Java is available." >&2
  return 1
}

# Merge a skill's hook.json into ~/.claude/settings.json.
# Args: skill_name, repo_dir
wire_hook() {
  local skill="$1" repo_dir="$2"
  local hook_path="$repo_dir/skills/$skill/hook.json"
  local settings="$HOME/.claude/settings.json"

  if [[ ! -f "$hook_path" ]]; then
    echo "  ERROR: $skill has no hook.json at $hook_path" >&2
    return 1
  fi

  if [[ "$skill" == "polish-input" ]]; then
    ensure_java || true
    echo "  Installing language_tool_python via pip..."
    pip install --user --quiet language_tool_python || {
      echo "  WARNING: pip install language_tool_python failed. Hook will fail open." >&2
    }
  fi

  echo "  Merging $skill hook into $settings..."
  python3 "$repo_dir/scripts/_settings_merge.py" --merge "$hook_path" "$settings"
  echo "  Hook wired."
}
```

- [ ] **Step 4: Verify shellcheck passes**

Run:
```bash
shellcheck scripts/install.sh scripts/_lib.sh
```

Expected: no errors. (Warnings about `read -r reply` without prompt are acceptable; we already echo the prompt.)

- [ ] **Step 5: Smoke-test the merge logic with a fake hook**

Run:
```bash
TMPDIR_T=$(mktemp -d)
cp skills/polish-input/hook.json "$TMPDIR_T/hook.json"
echo '{}' > "$TMPDIR_T/settings.json"
python3 scripts/_settings_merge.py --merge "$TMPDIR_T/hook.json" "$TMPDIR_T/settings.json"
cat "$TMPDIR_T/settings.json"
rm -rf "$TMPDIR_T"
```

Expected output contains `"UserPromptSubmit"` with the polish.py command.

- [ ] **Step 6: Commit**

```bash
git add scripts/install.sh scripts/_lib.sh
git commit -m "feat(install): --with-hook flag wires UserPromptSubmit hooks"
```

---

## Task 9: uninstall.sh — `--with-hook` Flag

**Files:**
- Modify: `scripts/uninstall.sh`

Mirror of Task 7. Same flag parsing, but at the end of the script we run `_settings_merge.py --remove`.

- [ ] **Step 1: Add the argument parsing**

In `scripts/uninstall.sh`, replace the existing argument-parsing `while` loop with:

```bash
AGENT_ARG=""
HOOK_SKILLS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)    AGENT_ARG="$2"; shift 2 ;;
    --agent=*)  AGENT_ARG="${1#*=}"; shift ;;
    --with-hook)    HOOK_SKILLS+=("$2"); shift 2 ;;
    --with-hook=*)  HOOK_SKILLS+=("${1#*=}"); shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
```

- [ ] **Step 2: Add the un-wire step at the end of uninstall.sh**

Just before the final closing of `uninstall.sh`, insert:

```bash
if [[ ${#HOOK_SKILLS[@]} -gt 0 ]]; then
  echo ""
  echo "==> Un-wiring hooks..."
  for skill in "${HOOK_SKILLS[@]}"; do
    unwire_hook "$skill" "$REPO_DIR"
  done
fi
```

- [ ] **Step 3: Add the `unwire_hook` function to `_lib.sh`**

Append to `scripts/_lib.sh`:

```bash
# Remove a skill's hook entry from ~/.claude/settings.json. Idempotent.
# Args: skill_name, repo_dir
unwire_hook() {
  local skill="$1" repo_dir="$2"
  local hook_path="$repo_dir/skills/$skill/hook.json"
  local settings="$HOME/.claude/settings.json"

  if [[ ! -f "$hook_path" ]]; then
    echo "  WARNING: $skill has no hook.json; nothing to remove." >&2
    return 0
  fi
  if [[ ! -f "$settings" ]]; then
    echo "  No $settings; nothing to remove."
    return 0
  fi

  echo "  Removing $skill hook from $settings..."
  python3 "$repo_dir/scripts/_settings_merge.py" --remove "$hook_path" "$settings"
}
```

- [ ] **Step 4: Verify shellcheck passes**

Run:
```bash
shellcheck scripts/uninstall.sh scripts/_lib.sh
```

Expected: no errors.

- [ ] **Step 5: Smoke-test the remove logic end-to-end**

Run:
```bash
TMPDIR_T=$(mktemp -d)
cp skills/polish-input/hook.json "$TMPDIR_T/hook.json"
echo '{"hooks":{"UserPromptSubmit":[{"command":"python3 ~/.claude/skills/polish-input/lib/polish.py"},{"command":"user-thing"}]}}' > "$TMPDIR_T/settings.json"
python3 scripts/_settings_merge.py --remove "$TMPDIR_T/hook.json" "$TMPDIR_T/settings.json"
cat "$TMPDIR_T/settings.json"
rm -rf "$TMPDIR_T"
```

Expected: only `user-thing` remains.

- [ ] **Step 6: Commit**

```bash
git add scripts/uninstall.sh scripts/_lib.sh
git commit -m "feat(uninstall): --with-hook flag un-wires UserPromptSubmit hooks"
```

---

## Task 10: Integration Smoke Test

**Files:**
- Create: `skills/polish-input/tests/integration_polish.sh`

A bash test that pipes a known-bad sentence through the actual `polish.py` against real LanguageTool. Skipped automatically when Java is missing.

- [ ] **Step 1: Write the test script**

Write `skills/polish-input/tests/integration_polish.sh`:

```bash
#!/usr/bin/env bash
# Integration test for polish-input. Requires Java + language_tool_python.
# Skips with exit 0 if either is missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLISH="$SCRIPT_DIR/../lib/polish.py"

if ! command -v java &>/dev/null; then
  echo "SKIP: java not found"
  exit 0
fi
if ! python3 -c "import language_tool_python" 2>/dev/null; then
  echo "SKIP: language_tool_python not installed"
  exit 0
fi

OUT_FILE=$(mktemp)
ERR_FILE=$(mktemp)
trap 'rm -f "$OUT_FILE" "$ERR_FILE"' EXIT

echo "i want add login" | python3 "$POLISH" >"$OUT_FILE" 2>"$ERR_FILE"

# stdout must be the original (replace mode is not set).
if [[ "$(cat "$OUT_FILE")" != "i want add login" ]]; then
  echo "FAIL: stdout was $(cat "$OUT_FILE")"
  exit 1
fi

# stderr must contain the [polish] prefix.
if ! grep -q '^\[polish\]' "$ERR_FILE"; then
  echo "FAIL: stderr did not contain [polish] line:"
  cat "$ERR_FILE"
  exit 1
fi

echo "OK"
```

Make it executable:
```bash
chmod +x skills/polish-input/tests/integration_polish.sh
```

- [ ] **Step 2: Run the test (it will skip if Java missing)**

Run:
```bash
bash skills/polish-input/tests/integration_polish.sh
```

Expected: prints `SKIP: java not found` or `SKIP: language_tool_python not installed` or `OK`. Exit code 0 in all three cases.

- [ ] **Step 3: Run the full unit test suite to confirm no regressions**

Run:
```bash
python3 -m pytest skills/polish-input/tests/test_polish.py tests/test_settings_merge.py -v
```

Expected: 23 passed (17 polish + 6 merge).

- [ ] **Step 4: Commit**

```bash
git add skills/polish-input/tests/integration_polish.sh
git commit -m "test(polish-input): integration smoke test gated on Java availability"
```

---

## Task 11: Acceptance Walk-through

**Files:** none (verification only)

This task validates the spec's acceptance criteria against the working tree. Do not commit anything.

- [ ] **Step 1: Confirm files match the file structure table**

Run:
```bash
ls skills/polish-input/ skills/polish-input/lib/ skills/polish-input/tests/
test -f scripts/_settings_merge.py
grep -q "^local  polish-input$" registry.txt
grep -q "with-hook" scripts/install.sh
grep -q "with-hook" scripts/uninstall.sh
```

Expected: all commands succeed.

- [ ] **Step 2: Confirm full unit test suite passes**

Run:
```bash
python3 -m pytest skills/polish-input/tests/test_polish.py tests/test_settings_merge.py -v
```

Expected: 23 passed.

- [ ] **Step 3: Dry-run the install path against a temp settings file**

Run:
```bash
TMP_SETTINGS=$(mktemp)
echo '{}' > "$TMP_SETTINGS"
python3 scripts/_settings_merge.py --merge skills/polish-input/hook.json "$TMP_SETTINGS"
cat "$TMP_SETTINGS"
python3 scripts/_settings_merge.py --remove skills/polish-input/hook.json "$TMP_SETTINGS"
cat "$TMP_SETTINGS"
rm "$TMP_SETTINGS"
```

Expected: after merge, `UserPromptSubmit` appears with the polish command; after remove, the file is `{}` (or `{"hooks": {}}` collapsed to `{}`).

- [ ] **Step 4: Sanity-check polish.py with a real prompt (if Java present)**

Run:
```bash
bash skills/polish-input/tests/integration_polish.sh
```

Expected: `SKIP` (no Java) or `OK`. Either is acceptable.

- [ ] **Step 5: Verify acceptance criteria from the spec**

Tick each acceptance criterion from `docs/superpowers/specs/2026-05-22-polish-input-design.md` against what's now in the tree:

1. `--with-hook polish-input` flag exists in install.sh — verified by Task 8 grep.
2. Default mode shows `[polish]` line on stderr, original on stdout — covered by `test_changed_text_emits_stderr_and_keeps_stdout_original`.
3. `POLISH_REPLACE=1` swaps stdout to polished — covered by `test_replace_mode_sends_polished_to_stdout`.
4. `POLISH_DISABLE=1` makes hook a no-op — covered by `test_disable_env_skips`.
5. Multi-line and slash-command prompts pass through silently — covered by `test_multi_line_skips`, `test_slash_command_skips`.
6. Uninstall removes the hook entry — covered by `test_remove_hook_only_drops_matching_entry`.
7. Unit tests pass on a machine without Java — confirmed by Step 2 (the test_polish suite uses `POLISH_TEST_FAKE_LT`).

- [ ] **Step 6: Final clean status check**

Run:
```bash
git status
git log --oneline -10
```

Expected: clean working tree; recent commits show the eight feature commits from this plan.
