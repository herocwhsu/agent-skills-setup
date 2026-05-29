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


def _install_fake_anthropic(monkeypatch, response_text=None, raises=None, blocks=None):
    """Stub the `anthropic` module with a controllable client.

    Pass `response_text` for a single text block, or `blocks` for an explicit
    list of (type, text_or_thinking) tuples to simulate mixed content (e.g.,
    a ThinkingBlock followed by a TextBlock as the Kiro gateway returns).
    """
    fake = types.ModuleType("anthropic")

    class _Block:
        def __init__(self, type_, text):
            self.type = type_
            self.text = text

    class _Resp:
        def __init__(self):
            if blocks is not None:
                self.content = [_Block(t, txt) for t, txt in blocks]
            else:
                self.content = [_Block("text", response_text)]

    class _Messages:
        def create(self, **kwargs):
            if raises is not None:
                raise raises
            self.last_call = kwargs
            return _Resp()

    class _Client:
        def __init__(self, **_kwargs):
            self.messages = _Messages()
            fake._last_messages = self.messages  # capture for assertions

    fake.Anthropic = _Client
    fake._last_messages = None
    monkeypatch.setitem(sys.modules, "anthropic", fake)
    return fake


def test_polish_returns_rewritten_text(monkeypatch):
    _install_fake_anthropic(monkeypatch, response_text="I want to add a new feature.")
    sys.modules.pop("polish_engine", None)
    import polish_engine
    out = polish_engine.polish("i want add new feature")
    assert out == "I want to add a new feature."


def test_polish_returns_none_when_sdk_missing(monkeypatch):
    monkeypatch.setitem(sys.modules, "anthropic", None)
    sys.modules.pop("polish_engine", None)
    import polish_engine
    out = polish_engine.polish("hello")
    assert out is None


def test_polish_returns_none_on_api_error(monkeypatch):
    _install_fake_anthropic(monkeypatch, raises=RuntimeError("boom"))
    sys.modules.pop("polish_engine", None)
    import polish_engine
    out = polish_engine.polish("hello")
    assert out is None


def test_polish_uses_model_env_var(monkeypatch):
    fake = _install_fake_anthropic(monkeypatch, response_text="ok")
    monkeypatch.setenv("POLISH_MODEL", "claude-sonnet-4-6")
    sys.modules.pop("polish_engine", None)
    import polish_engine
    polish_engine.polish("hi")
    assert fake._last_messages is not None
    assert fake._last_messages.last_call["model"] == "claude-sonnet-4-6"


def test_polish_uses_default_model_when_env_unset(monkeypatch):
    fake = _install_fake_anthropic(monkeypatch, response_text="ok")
    sys.modules.pop("polish_engine", None)
    import polish_engine
    polish_engine.polish("hi")
    assert fake._last_messages is not None
    assert fake._last_messages.last_call["model"] == "claude-haiku-4-5"


def test_polish_strips_whitespace(monkeypatch):
    _install_fake_anthropic(monkeypatch, response_text="  trimmed text  \n")
    sys.modules.pop("polish_engine", None)
    import polish_engine
    assert polish_engine.polish("anything") == "trimmed text"


def test_polish_skips_thinking_block_and_returns_text_block(monkeypatch):
    # Kiro gateway returns extended-thinking responses where content[0] is a
    # thinking block and content[1] is the actual text. polish() must not
    # crash on the thinking block (which has no usable .text for our purpose).
    _install_fake_anthropic(
        monkeypatch,
        blocks=[("thinking", "let me consider"), ("text", "I want to add a login.")],
    )
    sys.modules.pop("polish_engine", None)
    import polish_engine
    assert polish_engine.polish("i want add login") == "I want to add a login."


def test_polish_returns_none_when_no_text_block(monkeypatch):
    _install_fake_anthropic(monkeypatch, blocks=[("thinking", "only thinking")])
    sys.modules.pop("polish_engine", None)
    import polish_engine
    assert polish_engine.polish("hi") is None
