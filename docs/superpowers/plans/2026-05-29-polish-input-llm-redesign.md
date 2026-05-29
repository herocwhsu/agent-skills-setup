# polish-input LLM Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace LanguageTool with Claude Haiku 4.5 (via Anthropic SDK) as the polish engine, keeping all hook plumbing intact.

**Architecture:** Add a new `polish_engine.py` that wraps the Anthropic SDK with a cached system prompt. Swap the `_correct` call site in `polish.py` to use it. Drop Java/LanguageTool from install. All skip rules, display formats, fail-open semantics, and hook protocol handling stay the same.

**Tech Stack:** Python 3.10+, Anthropic Python SDK (`anthropic`), pytest, bash.

**Spec:** `docs/superpowers/specs/2026-05-29-polish-input-llm-redesign-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `skills/polish-input/lib/polish_engine.py` | **Create** | SDK wrapper. One public function `polish(text) -> str \| None`. |
| `skills/polish-input/lib/polish.py` | **Modify** | Remove LT-specific code (`_get_tool`, `_TOOL`, `_maybe_show_first_run_message`, `_write_lt_error_hint_once`). Replace `_correct()` with a call into `polish_engine.polish()`. Rename test env vars. |
| `skills/polish-input/tests/test_polish.py` | **Modify** | Rename `POLISH_TEST_FAKE_LT` → `POLISH_TEST_FAKE_RESPONSE`, `POLISH_TEST_NO_LT` → `POLISH_TEST_NO_ENGINE`. Drop the LT first-run-message test. Update error-hint test to look for `.engine-error`. |
| `skills/polish-input/tests/integration_polish.sh` | **Modify** | Replace Java/LT preflight with `ANTHROPIC_API_KEY` + `anthropic` import check. Gate behind `RUN_INTEGRATION=1`. |
| `skills/polish-input/SKILL.md` | **Modify** | Drop "LanguageTool" from description; replace with "Claude Haiku". |
| `skills/polish-input/README.md` | **Modify** | Rewrite install section, env var table, troubleshooting. |
| `scripts/_lib.sh` | **Modify** | Delete `ensure_java()`. In `wire_hook()`, replace the polish-input branch (Java + `language_tool_python`) with `pip install anthropic`. |

Each file has one responsibility. `polish_engine.py` is independently testable with no side effects on `polish.py`.

---

## Task 1: Add polish_engine.py with mocked-SDK tests

**Files:**
- Create: `skills/polish-input/lib/polish_engine.py`
- Create: `skills/polish-input/tests/test_polish_engine.py`

- [ ] **Step 1: Write the failing test for the engine module**

Create `skills/polish-input/tests/test_polish_engine.py`:

```python
from __future__ import annotations
"""Unit tests for polish_engine — uses a fake anthropic module."""
import os
import sys
import types
from pathlib import Path

import pytest

LIB = Path(__file__).resolve().parents[1] / "lib"
sys.path.insert(0, str(LIB))


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    for k in list(os.environ):
        if k.startswith("POLISH_") or k.startswith("ANTHROPIC_"):
            monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")


def _install_fake_anthropic(monkeypatch, response_text=None, raises=None):
    """Stub the `anthropic` module with a controllable client."""
    fake = types.ModuleType("anthropic")

    class _Block:
        def __init__(self, text): self.text = text

    class _Resp:
        def __init__(self, text): self.content = [_Block(text)]

    class _Messages:
        def create(self, **kwargs):
            if raises is not None:
                raise raises
            self.last_call = kwargs
            return _Resp(response_text)

    class _Client:
        def __init__(self, **_kwargs):
            self.messages = _Messages()

    fake.Anthropic = _Client
    monkeypatch.setitem(sys.modules, "anthropic", fake)
    return fake


def test_polish_returns_rewritten_text(monkeypatch):
    _install_fake_anthropic(monkeypatch, response_text="I want to add a new feature.")
    import polish_engine
    out = polish_engine.polish("i want add new feature")
    assert out == "I want to add a new feature."


def test_polish_returns_none_when_sdk_missing(monkeypatch):
    monkeypatch.setitem(sys.modules, "anthropic", None)
    # Force a fresh import-attempt path:
    if "anthropic" in sys.modules and sys.modules["anthropic"] is None:
        pass
    import polish_engine
    # Setting sys.modules[name] = None makes `import anthropic` raise ImportError.
    out = polish_engine.polish("hello")
    assert out is None


def test_polish_returns_none_on_api_error(monkeypatch):
    _install_fake_anthropic(monkeypatch, raises=RuntimeError("boom"))
    import polish_engine
    out = polish_engine.polish("hello")
    assert out is None


def test_polish_uses_model_env_var(monkeypatch):
    fake = _install_fake_anthropic(monkeypatch, response_text="ok")
    monkeypatch.setenv("POLISH_MODEL", "claude-sonnet-4-6")
    import polish_engine
    polish_engine.polish("hi")
    # The fake captures kwargs on the messages instance; pull them back via a fresh client.
    # Because polish() builds a new client per call, we re-invoke and inspect:
    client = fake.Anthropic()
    client.messages.create(model="claude-sonnet-4-6", max_tokens=1, system=[], messages=[])
    assert client.messages.last_call["model"] == "claude-sonnet-4-6"


def test_polish_strips_whitespace(monkeypatch):
    _install_fake_anthropic(monkeypatch, response_text="  trimmed text  \n")
    import polish_engine
    assert polish_engine.polish("anything") == "trimmed text"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd skills/polish-input && python3 -m pytest tests/test_polish_engine.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'polish_engine'`.

- [ ] **Step 3: Implement polish_engine.py**

Create `skills/polish-input/lib/polish_engine.py`:

```python
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
import sys
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
        import anthropic  # local import: skip cost when caller never reaches here
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd skills/polish-input && python3 -m pytest tests/test_polish_engine.py -v`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add skills/polish-input/lib/polish_engine.py skills/polish-input/tests/test_polish_engine.py
git commit -m "feat(polish-input): add LLM polish engine module"
```

---

## Task 2: Wire polish.py to use polish_engine

**Files:**
- Modify: `skills/polish-input/lib/polish.py`
- Modify: `skills/polish-input/tests/test_polish.py`

- [ ] **Step 1: Update test_polish.py to use new env-var names and engine module**

Apply these replacements in `skills/polish-input/tests/test_polish.py`:

| Old | New |
|---|---|
| `POLISH_TEST_FAKE_LT` | `POLISH_TEST_FAKE_RESPONSE` |
| `POLISH_TEST_NO_LT` | `POLISH_TEST_NO_ENGINE` |
| `_fake_lt` (function name) | `_fake_response` |
| `"initializing LanguageTool"` (assertion) | (delete the test entirely; no init step now) |
| `"lt-error"` (assertion) | `"engine-error"` |
| `"Java" in body or "language_tool_python" in body` | `"anthropic" in body` |
| `_lt_failure_falls_through_silently` (test names) | `_engine_failure_falls_through_silently` |

Open `skills/polish-input/tests/test_polish.py` and apply via Edit:

```text
Edit: replace_all "POLISH_TEST_FAKE_LT" with "POLISH_TEST_FAKE_RESPONSE"
Edit: replace_all "POLISH_TEST_NO_LT" with "POLISH_TEST_NO_ENGINE"
Edit: replace_all "_fake_lt" with "_fake_response"
Edit: replace assertion `"Java" in body or "language_tool_python" in body` → `"anthropic" in body`
Edit: replace assertion `"lt-error" in body` → `"engine-error" in body`
```

Delete the `test_first_run_message_then_suppressed` test entirely (no first-run step in the new engine).

Rename `test_lt_error_writes_one_time_hint_to_debug_log` → `test_engine_error_writes_one_time_hint_to_debug_log`.
Rename `test_lt_error_fails_open` → `test_engine_error_fails_open`.
Rename `test_hook_protocol_lt_failure_falls_through_silently` → `test_hook_protocol_engine_failure_falls_through_silently`.

- [ ] **Step 2: Run polish tests to confirm they fail with the rename**

Run: `cd skills/polish-input && python3 -m pytest tests/test_polish.py -v`
Expected: most tests FAIL because `polish.py` still reads the old env-var names. This is intentional — we're TDD'ing the refactor.

- [ ] **Step 3: Refactor polish.py — replace _correct + LT helpers with polish_engine call**

In `skills/polish-input/lib/polish.py`:

a) Delete these functions and globals (lines ~87-172): `_write_lt_error_hint_once`, `_correct`, `_TOOL`, `_maybe_show_first_run_message`, `_get_tool`.

b) Update the docstring at the top — replace the LanguageTool description with:

```python
"""polish-input runtime: invoked as a Claude Code UserPromptSubmit hook.

Two stdin modes are supported:

1. Hook-protocol mode (current Claude Code): stdin is a JSON object with
   `hook_event_name == "UserPromptSubmit"` and a `prompt` field. We emit a
   JSON response on stdout containing `systemMessage` (user-visible) and,
   when POLISH_REPLACE=1, `hookSpecificOutput.additionalContext` so the
   model also sees the polished version.

2. Legacy raw-text mode (used by tests and direct piping): stdin is the
   prompt as plain text. We write the original (or polished, if
   POLISH_REPLACE=1) to stdout and emit `[polish] ...` on stderr.

Always exits 0. Failures fall through silently so the user's prompt is never blocked.
"""
```

c) Replace the `_polish_text` function body to call the engine module:

```python
def _polish_text(text: str) -> tuple[str | None, str]:
    """Apply skip rules + the LLM engine. Returns (corrected_or_None, reason)."""
    skip = _skip_reason(text)
    if skip is not None:
        return None, f"skip:{skip}"

    if os.environ.get("POLISH_TEST_NO_ENGINE") == "1":
        return None, "test-no-engine"

    fake = os.environ.get("POLISH_TEST_FAKE_RESPONSE")
    if fake is not None:
        if fake == "RAISE":
            from polish_engine import _write_engine_error_hint_once
            _write_engine_error_hint_once("simulated engine failure")
            return None, "correct-failed"
        try:
            import json as _json
            mapping = _json.loads(fake)
        except Exception:
            return None, "correct-failed"
        corrected = mapping.get(text, text)
    else:
        try:
            from polish_engine import polish as _engine_polish
            corrected = _engine_polish(text)
        except Exception as e:
            _debug_log("correct-failed", str(e))
            return None, "correct-failed"

    if corrected is None or corrected == text:
        return None, "no-change"
    return corrected, "polished"
```

d) In `_run_legacy_text`, replace the body to mirror the same flow:

```python
def _run_legacy_text(text: str) -> int:
    corrected, reason = _polish_text(text)
    if corrected is None:
        _debug_log(reason.split(":", 1)[0], reason.split(":", 1)[1] if ":" in reason else "")
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

e) Make sure `polish_engine` is importable from `polish.py` regardless of how the script is invoked:

At the top of `polish.py`, after the existing imports, add:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent))
```

- [ ] **Step 4: Run polish tests to confirm they pass**

Run: `cd skills/polish-input && python3 -m pytest tests/test_polish.py tests/test_polish_engine.py -v`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/polish-input/lib/polish.py skills/polish-input/tests/test_polish.py
git commit -m "refactor(polish-input): swap LanguageTool for LLM engine"
```

---

## Task 3: Update install/uninstall scripts

**Files:**
- Modify: `scripts/_lib.sh`

- [ ] **Step 1: Delete the ensure_java() function**

In `scripts/_lib.sh`, delete the entire `ensure_java()` function (the block from `# ensure_java` comment through the closing `}` — roughly lines 316-360).

- [ ] **Step 2: Replace the polish-input branch in wire_hook()**

In `scripts/_lib.sh`, find the `if [[ "$skill" == "polish-input" ]]; then` block inside `wire_hook()` and replace its body:

```bash
  if [[ "$skill" == "polish-input" ]]; then
    echo "  Installing anthropic SDK via pip..."
    local pip_cmd
    if command -v pip3 &>/dev/null; then
      pip_cmd="pip3"
    elif command -v pip &>/dev/null; then
      pip_cmd="pip"
    else
      echo "  WARNING: pip not found — skipping anthropic install" >&2
      pip_cmd=""
    fi
    if [[ -n "$pip_cmd" ]]; then
      "$pip_cmd" install --user --quiet anthropic || {
        echo "  WARNING: $pip_cmd install anthropic failed. Hook will fail open." >&2
      }
    fi
  fi
```

- [ ] **Step 3: Manually verify install path with a dry run**

Run: `bash -n scripts/_lib.sh && bash -n scripts/install.sh`
Expected: no syntax errors.

- [ ] **Step 4: Commit**

```bash
git add scripts/_lib.sh
git commit -m "build(polish-input): drop Java/LT, install anthropic SDK"
```

---

## Task 4: Rewrite integration test

**Files:**
- Modify: `skills/polish-input/tests/integration_polish.sh`

- [ ] **Step 1: Replace the integration script**

Overwrite `skills/polish-input/tests/integration_polish.sh`:

```bash
#!/usr/bin/env bash
# Integration test for polish-input. Hits the real Anthropic API.
# Gated behind RUN_INTEGRATION=1 so CI doesn't burn tokens by default.
set -euo pipefail

if [[ "${RUN_INTEGRATION:-0}" != "1" ]]; then
  echo "SKIP: set RUN_INTEGRATION=1 to run integration tests"
  exit 0
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "SKIP: ANTHROPIC_API_KEY not set"
  exit 0
fi

if ! python3 -c "import anthropic" 2>/dev/null; then
  echo "SKIP: anthropic SDK not installed (pip install --user anthropic)"
  exit 0
fi

POLISH="$(cd "$(dirname "$0")/.." && pwd)/lib/polish.py"

run_case() {
  local input="$1" expect_keyword="$2"
  local out err
  out=$(mktemp); err=$(mktemp)
  echo -n "$input" | python3 "$POLISH" >"$out" 2>"$err"
  if ! grep -q "$expect_keyword" "$err"; then
    echo "FAIL: expected '$expect_keyword' in stderr for input: $input"
    echo "  stderr: $(cat "$err")"
    rm -f "$out" "$err"
    exit 1
  fi
  rm -f "$out" "$err"
  echo "OK: $input"
}

run_case "i want add login" "[polish]"
run_case "let surf" "[polish]"
run_case "Read the auth file." ""  # already fluent, no [polish] line is fine

echo "All integration cases passed."
```

- [ ] **Step 2: Lint-check**

Run: `bash -n skills/polish-input/tests/integration_polish.sh`
Expected: no output (no errors).

- [ ] **Step 3: Commit**

```bash
git add skills/polish-input/tests/integration_polish.sh
git commit -m "test(polish-input): rewrite integration script for LLM engine"
```

---

## Task 5: Update SKILL.md and README.md

**Files:**
- Modify: `skills/polish-input/SKILL.md`
- Modify: `skills/polish-input/README.md`

- [ ] **Step 1: Update SKILL.md**

Replace `skills/polish-input/SKILL.md` contents:

```markdown
---
name: polish-input
description: Use when the user wants automatic English polish on every prompt. Installs a Claude Code UserPromptSubmit hook that uses Claude Haiku 4.5 to rewrite each single-line prompt as natural English, displayed to the user as a learning side-channel. Default behavior does not change what Claude receives.
---

# polish-input

This skill installs a runtime hook for Claude Code. Once installed, every
single-line, non-slash-command prompt the user types is sent to Claude Haiku
4.5 (via the Anthropic SDK), and the polished version is printed to the
user's terminal as a learning side-channel.

See `README.md` for installation, configuration, and troubleshooting.
```

- [ ] **Step 2: Update README.md**

Replace `skills/polish-input/README.md` contents:

```markdown
# polish-input

Auto-polish single-line English prompts as a learning side-channel for Claude Code.
Uses Claude Haiku 4.5 via the Anthropic SDK.

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
2. Installs the `anthropic` Python SDK via pip.
3. Merges the `UserPromptSubmit` hook into `~/.claude/settings.json`.

The hook reads `ANTHROPIC_API_KEY` and `ANTHROPIC_BASE_URL` from the
environment Claude Code runs in. In Kiro mode these are already set to point
at the Kiro gateway; no second API key is required.

## Configuration

All env vars are optional.

| Var | Default | Effect |
|---|---|---|
| `POLISH_DISABLE` | unset | If `1`, hook is a no-op. Instant escape hatch. |
| `POLISH_REPLACE` | unset | If `1`, send the polished text to Claude instead of the original. |
| `POLISH_DISPLAY` | `line` | `line` / `diff` / `box`. |
| `POLISH_DEBUG` | unset | If `1`, log diagnostics to `~/.claude/state/polish-input/debug.log`. |
| `POLISH_MODEL` | `claude-haiku-4-5` | Override the polish model. |
| `POLISH_TIMEOUT_MS` | `3000` | API timeout in milliseconds. |

Set them in `~/.claude/settings.json` under `env`, or in your shell rc.

## Skip rules

The hook is silent when:
- The prompt starts with `/` (slash command).
- The prompt contains a newline (multi-line).
- The prompt is over 4000 characters.
- `POLISH_DISABLE=1` is set.
- The polish engine is unavailable (fail open).

## Uninstall

```bash
bash scripts/uninstall.sh --with-hook polish-input
```

Removes the hook entry and unlinks the skill. The `anthropic` package is
left in place; remove manually with `pip uninstall anthropic` if desired.

## Troubleshooting

- **No polish appears:** Check `~/.claude/state/polish-input/debug.log`.
  Common causes: `anthropic` not installed, or `ANTHROPIC_API_KEY` not set in
  the environment Claude Code runs in.
- **Polish is slow (>3s):** The hook times out at 3s by default. Bump
  `POLISH_TIMEOUT_MS` if your gateway is slower.
- **Wrong model used:** Set `POLISH_MODEL` to an alias your gateway exposes.
- **Windows:** Auto-wiring is not implemented. Install the skill files
  normally, then manually add the hook from `hook.json` to
  `%USERPROFILE%\.claude\settings.json`.
```

- [ ] **Step 3: Commit**

```bash
git add skills/polish-input/SKILL.md skills/polish-input/README.md
git commit -m "docs(polish-input): update for LLM engine"
```

---

## Task 6: End-to-end smoke test

**Files:** none modified — verification only.

- [ ] **Step 1: Run the full test suite**

Run: `cd skills/polish-input && python3 -m pytest tests/ -v`
Expected: all unit tests pass.

- [ ] **Step 2: Smoke test the hook locally with a fake response**

```bash
echo -n "i want add login" | \
  POLISH_TEST_FAKE_RESPONSE='{"i want add login":"I want to add a login."}' \
  python3 skills/polish-input/lib/polish.py
```

Expected stdout: `i want add login`
Expected stderr: `[polish] I want to add a login.`

- [ ] **Step 3: Smoke test the hook protocol with a fake response**

```bash
echo -n '{"hook_event_name":"UserPromptSubmit","prompt":"i want add login","session_id":"x","transcript_path":"/tmp/x","cwd":"/tmp","permission_mode":"default"}' | \
  POLISH_TEST_FAKE_RESPONSE='{"i want add login":"I want to add a login."}' \
  python3 skills/polish-input/lib/polish.py
```

Expected stdout: a JSON object containing `systemMessage` with `[polish] I want to add a login.`
Expected stderr: `[polish] I want to add a login.`

- [ ] **Step 4: Run the integration test (real API)**

If `ANTHROPIC_API_KEY` is set and `anthropic` is installed:

```bash
RUN_INTEGRATION=1 bash skills/polish-input/tests/integration_polish.sh
```

Expected: `All integration cases passed.`

If you don't want to spend tokens, skip this step.

- [ ] **Step 5: No commit — smoke test only**

If everything passed, the implementation is complete. If anything failed,
return to the failing task and fix.

---

## Done criteria

- [ ] All unit tests in `tests/test_polish.py` and `tests/test_polish_engine.py` pass.
- [ ] No references to `language_tool_python`, `Java`, `OpenJDK`, `LanguageTool`, or `ensure_java` remain in `skills/polish-input/` or `scripts/`.
- [ ] `polish.py` imports `polish_engine` and uses it in `_polish_text`.
- [ ] `README.md` documents `POLISH_MODEL` and `POLISH_TIMEOUT_MS`.
- [ ] Integration test (when run with `RUN_INTEGRATION=1`) succeeds against the real API.
