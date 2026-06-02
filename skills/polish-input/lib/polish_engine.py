#!/usr/bin/env python3
"""LLM-backed polish engine.

AuthProvider subclasses supply credentials; polish() tries each in order and
returns the first successful rewrite. Callers build the provider list based on
the detected agent context (see polish.py).
"""
from __future__ import annotations

import datetime
import json
import os
import subprocess
from pathlib import Path
from typing import Any

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
DEFAULT_STATE_DIR = "~/.agent-skills-setup/state/polish-input"


# ---------------------------------------------------------------------------
# State / logging
# ---------------------------------------------------------------------------

def _state_dir() -> Path:
    raw = os.environ.get("POLISH_STATE_DIR") or DEFAULT_STATE_DIR
    path = Path(os.path.expanduser(raw))
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_engine_error_hint_once(reason: str) -> None:
    marker = _state_dir() / ".engine-error"
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
    backend: str    # "anthropic" | "gemini"
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


class GeminiSessionProvider(AuthProvider):
    """OAuth credentials from the active Gemini CLI login session."""
    name = "gemini-session"
    backend = "gemini"
    cred_type = "oauth"

    def credential(self) -> Any:
        try:
            import google.oauth2.credentials
            creds_path = Path(os.path.expanduser("~/.gemini/oauth_creds.json"))
            if not creds_path.exists():
                return None
            data = json.loads(creds_path.read_text())
            return google.oauth2.credentials.Credentials(
                token=data.get("access_token"),
                refresh_token=data.get("refresh_token"),
                token_uri="https://oauth2.googleapis.com/token",
                client_id="681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com",
                client_secret=None,
            )
        except Exception:
            return None


class GeminiKeyProvider(AuthProvider):
    """API key from the GEMINI_API_KEY environment variable."""
    name = "gemini-key"
    backend = "gemini"
    cred_type = "key"

    def credential(self) -> str | None:
        return os.environ.get("GEMINI_API_KEY") or None


class GeminiKeychainProvider(AuthProvider):
    """API key from the agent-skills-setup keychain (secret-tool or credentials.json)."""
    name = "gemini-keychain"
    backend = "gemini"
    cred_type = "key"

    def credential(self) -> str | None:
        try:
            user = "default"
            config_path = Path(os.path.expanduser("~/.agent-skills-setup/config.sh"))
            if config_path.exists():
                for line in config_path.read_text().splitlines():
                    if line.startswith("GEMINI_USER="):
                        user = line.split("=", 1)[1].strip("\"' ")
                        break

            try:
                result = subprocess.run(
                    ["secret-tool", "lookup", "service", "agent-skills-setup:gemini", "username", user],
                    capture_output=True, text=True,
                )
                if result.returncode == 0 and result.stdout.strip():
                    return result.stdout.strip()
            except FileNotFoundError:
                pass

            fb = Path(os.path.expanduser("~/.agent-skills-setup/credentials.json"))
            if fb.exists():
                data = json.loads(fb.read_text())
                return data.get(f"agent-skills-setup:gemini:{user}") or None
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
            system=[{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
            messages=[{"role": "user", "content": text}],
        )
        for block in resp.content:
            if getattr(block, "type", None) == "text":
                return block.text.strip()
        return None
    except Exception as e:
        write_engine_error_hint_once(f"Anthropic API call failed: {e}")
        return None


def _polish_gemini(text: str, cred: Any, cred_type: str) -> str | None:
    try:
        import google.generativeai as genai
    except ImportError as e:
        write_engine_error_hint_once(f"google-generativeai SDK not importable: {e}")
        return None
    try:
        if cred_type == "oauth":
            genai.configure(credentials=cred)
        else:
            genai.configure(api_key=cred)
        timeout_ms = int(os.environ.get("POLISH_TIMEOUT_MS", str(DEFAULT_TIMEOUT_MS)))
        model = genai.GenerativeModel(model_name="gemini-1.5-flash", system_instruction=SYSTEM_PROMPT)
        response = model.generate_content(text, request_options={"timeout": timeout_ms / 1000})
        try:
            return response.text.strip() if response.text else None
        except (ValueError, AttributeError):
            return None
    except Exception as e:
        write_engine_error_hint_once(f"Gemini API call failed: {e}")
        return None


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def polish(text: str, providers: list[AuthProvider]) -> str | None:
    """Try each provider in order; return first successful rewrite, else None."""
    for p in providers:
        cred = p.credential()
        if cred is None:
            continue
        if p.backend == "anthropic":
            result = _polish_anthropic(text, cred, p.cred_type)
        elif p.backend == "gemini":
            result = _polish_gemini(text, cred, p.cred_type)
        else:
            continue
        if result is not None:
            return result
    return None
