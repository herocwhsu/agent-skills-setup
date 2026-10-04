#!/usr/bin/env python3
"""LLM-backed polish engine.

AuthProvider subclasses supply credentials; polish() tries each in order and
returns the first successful rewrite. Callers build the provider list based on
the detected agent context (see polish.py).
"""

from __future__ import annotations

import datetime
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path


def _repo_id(start: str) -> str:
    """Repo id from the nearest .skills-repo-id at or above `start`.

    Mirrors _skills_repo_id in lib/lib.sh. Two repos installed on one machine
    must not share a keychain prefix; absent a marker, keep the historical name.
    """
    d = Path(start).resolve()
    for cand in (d, *d.parents):
        marker = cand / ".skills-repo-id"
        if marker.is_file():
            return marker.read_text().split("\n")[0].strip() or "agent-skills-setup"
    return "agent-skills-setup"


_KEYCHAIN_PREFIX = _repo_id(__file__)
_GEMINI_SVC = f"{_KEYCHAIN_PREFIX}:gemini"
_FALLBACK_STORE = f"~/.{_KEYCHAIN_PREFIX}/credentials.json"
from typing import Any

SYSTEM_PROMPT = (
    "You are a copy editor, not an assistant. The user turn contains one message "
    "inside <text> tags. Rewrite only that message as natural English, keeping its "
    "meaning, person, and technical terms, code, file paths, URLs and command-line "
    "flags exactly. Never reply to it, answer it, or comment on it. Output only the "
    "rewritten message, with no tags. If it is already fluent, output it unchanged."
)


# Behind a gateway that adds its own system prompt (claude-kiro), a bare "yes"
# was answered as chat. The tags mark the message as text to rewrite.
def _wrap(text: str) -> str:
    return f"<text>{text}</text>"


def _unwrap(text: str) -> str:
    m = re.fullmatch(r"\s*<text>(.*)</text>\s*", text, re.DOTALL)
    return (m.group(1) if m else text).strip()

DEFAULT_MODEL = "claude-haiku-4-5"
DEFAULT_TIMEOUT_MS = 3000
DEFAULT_MAX_TOKENS = 1500
DEFAULT_STATE_DIR = f"~/.{_KEYCHAIN_PREFIX}/state/polish-input"


# ---------------------------------------------------------------------------
# State / logging
# ---------------------------------------------------------------------------


def _state_dir() -> Path:
    raw = os.environ.get("POLISH_STATE_DIR") or DEFAULT_STATE_DIR
    path = Path(os.path.expanduser(raw))
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_engine_error_hint_once(reason: str) -> None:
    # De-dupe on the reason's content hash, not a single global marker. A stale
    # marker from one early error must not silently swallow later errors with a
    # different cause (that masked a Gemini 403 during debugging). Same reason
    # still logs only once; a new distinct reason logs once more.
    digest = hashlib.sha1(reason.encode("utf-8", "replace")).hexdigest()[:12]
    marker = _state_dir() / f".engine-error-{digest}"
    if marker.exists():
        return
    hint = (
        f"engine-error: {reason}\n"
        "polish-input could not call the polish engine.\n"
        "Make sure the relevant SDK is installed and credentials are available.\n"
    )
    try:
        with (_state_dir() / "debug.log").open("a") as f:
            ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            f.write(f"[{ts}] {hint}")
        marker.touch()
    except OSError:
        pass


# ---------------------------------------------------------------------------
# AuthProvider hierarchy
# ---------------------------------------------------------------------------


class AuthProvider:
    """Base class. Subclasses define name, backend, cred_type, and credential()."""

    name: str
    backend: str  # "anthropic" | "gemini"
    cred_type: str  # "key" | "bearer" | "oauth"

    def credential(self) -> Any:
        raise NotImplementedError


class ClaudeSessionProvider(AuthProvider):
    """OAuth bearer token from the active Claude Code login session."""

    name = "claude-session"
    backend = "anthropic"
    cred_type = "bearer"

    def credential(self) -> str | None:
        import time

        # 1. macOS Keychain ("Claude Code-credentials")
        try:
            result = subprocess.run(
                [
                    "security",
                    "find-generic-password",
                    "-s",
                    "Claude Code-credentials",
                    "-w",
                ],
                capture_output=True,
                text=True,
                timeout=2,
            )
            if result.returncode == 0 and result.stdout.strip():
                data = json.loads(result.stdout.strip())
                oauth = data.get("claudeAiOauth", {})
                token = oauth.get("accessToken")
                expires_at_ms = oauth.get("expiresAt", 0)
                if token and time.time() * 1000 < expires_at_ms:
                    return token
        except Exception:
            pass

        # 2. Legacy/fallback credentials.json file
        creds_path = Path(os.path.expanduser("~/.claude/.credentials.json"))
        if not creds_path.exists():
            return None
        try:
            data = json.loads(creds_path.read_text())
            oauth = data.get("claudeAiOauth", {})
            token = oauth.get("accessToken")
            expires_at_ms = oauth.get("expiresAt", 0)
            if token and time.time() * 1000 < expires_at_ms:
                return token
        except Exception:
            pass
        return None


class AnthropicKeyProvider(AuthProvider):
    """API key from the ANTHROPIC_API_KEY environment variable."""

    name = "anthropic-key"
    backend = "anthropic"
    cred_type = "key"

    def credential(self) -> str | None:
        return os.environ.get("ANTHROPIC_API_KEY") or None


class GeminiKeyProvider(AuthProvider):
    """API key from the GEMINI_API_KEY environment variable."""

    name = "gemini-key"
    backend = "gemini"
    cred_type = "key"

    def credential(self) -> str | None:
        return os.environ.get("GEMINI_API_KEY") or None


class AnthropicKeychainProvider(AuthProvider):
    """API key from this runtime's keychain (security, secret-tool, or credentials.json)."""

    name = "anthropic-keychain"
    backend = "anthropic"
    cred_type = "key"

    def credential(self) -> str | None:
        try:
            user = "default"
            config_path = Path(os.path.expanduser(f"~/.{_KEYCHAIN_PREFIX}/config.sh"))
            if config_path.exists():
                for line in config_path.read_text().splitlines():
                    if line.startswith("ANTHROPIC_USER="):
                        user = line.split("=", 1)[1].strip("\"' ")
                        break

            svc = f"{_KEYCHAIN_PREFIX}:anthropic"
            try:
                result = subprocess.run(
                    [
                        "security",
                        "find-generic-password",
                        "-s",
                        svc,
                        "-a",
                        user,
                        "-w",
                    ],
                    capture_output=True,
                    text=True,
                )
                if result.returncode == 0 and result.stdout.strip():
                    return result.stdout.strip()
            except FileNotFoundError:
                pass

            try:
                result = subprocess.run(
                    [
                        "secret-tool",
                        "lookup",
                        "service",
                        svc,
                        "username",
                        user,
                    ],
                    capture_output=True,
                    text=True,
                )
                if result.returncode == 0 and result.stdout.strip():
                    return result.stdout.strip()
            except FileNotFoundError:
                pass

            fb = Path(os.path.expanduser(_FALLBACK_STORE))
            if fb.exists():
                data = json.loads(fb.read_text())
                return data.get(f"{svc}:{user}") or None
        except Exception:
            pass
        return None


class GeminiKeychainProvider(AuthProvider):
    """API key from this runtime's keychain (security, secret-tool, or credentials.json)."""

    name = "gemini-keychain"
    backend = "gemini"
    cred_type = "key"

    def credential(self) -> str | None:
        try:
            user = "default"
            config_path = Path(os.path.expanduser(f"~/.{_KEYCHAIN_PREFIX}/config.sh"))
            if config_path.exists():
                for line in config_path.read_text().splitlines():
                    if line.startswith("GEMINI_USER="):
                        user = line.split("=", 1)[1].strip("\"' ")
                        break

            try:
                result = subprocess.run(
                    [
                        "security",
                        "find-generic-password",
                        "-s",
                        _GEMINI_SVC,
                        "-a",
                        user,
                        "-w",
                    ],
                    capture_output=True,
                    text=True,
                )
                if result.returncode == 0 and result.stdout.strip():
                    return result.stdout.strip()
            except FileNotFoundError:
                pass

            try:
                result = subprocess.run(
                    [
                        "secret-tool",
                        "lookup",
                        "service",
                        _GEMINI_SVC,
                        "username",
                        user,
                    ],
                    capture_output=True,
                    text=True,
                )
                if result.returncode == 0 and result.stdout.strip():
                    return result.stdout.strip()
            except FileNotFoundError:
                pass

            fb = Path(os.path.expanduser(_FALLBACK_STORE))
            if fb.exists():
                data = json.loads(fb.read_text())
                return data.get(f"{_GEMINI_SVC}:{user}") or None
        except Exception:
            pass
        return None


# ---------------------------------------------------------------------------
# Backend callers
# ---------------------------------------------------------------------------


def _polish_anthropic(text: str, cred: str, cred_type: str) -> str | None:
    try:
        import anthropic
    except ImportError as e:
        write_engine_error_hint_once(f"anthropic SDK not importable: {e}")
        return None
    try:
        timeout_s = int(os.environ.get("POLISH_TIMEOUT_MS", str(DEFAULT_TIMEOUT_MS))) / 1000
        if cred_type == "bearer":
            client = anthropic.Anthropic(auth_token=cred)
        else:
            client = anthropic.Anthropic(api_key=cred)
        resp = client.messages.create(
            model=os.environ.get("POLISH_MODEL", DEFAULT_MODEL),
            max_tokens=DEFAULT_MAX_TOKENS,
            timeout=timeout_s,
            thinking={"type": "disabled"},
            system=[
                {"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}
            ],
            messages=[{"role": "user", "content": _wrap(text)}],
        )
        for block in resp.content:
            if getattr(block, "type", None) == "text":
                return _unwrap(getattr(block, "text", ""))
        return None
    except Exception as e:
        write_engine_error_hint_once(f"Anthropic API call failed: {e}")
        return None


def _polish_gemini(text: str, cred: str) -> str | None:
    try:
        from google import genai
        from google.genai import types
    except ImportError as e:
        write_engine_error_hint_once(f"google-genai SDK not importable: {e}")
        return None
    try:
        timeout_env = os.environ.get("POLISH_TIMEOUT_MS")
        timeout_ms = int(timeout_env) if timeout_env else 10000
        client = genai.Client(api_key=cred, http_options=types.HttpOptions(timeout=timeout_ms))
        response = client.models.generate_content(
            model=os.environ.get("POLISH_MODEL", "gemini-3.5-flash-lite"),
            contents=_wrap(text),
            config=types.GenerateContentConfig(system_instruction=SYSTEM_PROMPT),
        )
        return _unwrap(response.text) if response.text else None
    except Exception as e:
        write_engine_error_hint_once(f"Gemini API call failed: {e}")
        return None


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def polish(text: str, providers: list[AuthProvider]) -> str | None:
    """Try each provider in order; return first successful rewrite, else None."""
    gemini_without_key = False
    for p in providers:
        cred = p.credential()
        if cred is None:
            gemini_without_key = gemini_without_key or p.backend == "gemini"
            continue
        if p.backend == "anthropic":
            result = _polish_anthropic(text, cred, p.cred_type)
        elif p.backend == "gemini":
            result = _polish_gemini(text, cred)
        else:
            continue
        if result is not None:
            return result
    if gemini_without_key:
        # google-genai accepts only an API key for the Gemini API; OAuth sessions
        # (e.g. Antigravity's) work only in Vertex AI mode.
        write_engine_error_hint_once(
            "no Gemini API key: set GEMINI_API_KEY or store one as agent-skills-setup:gemini"
        )
    return None
