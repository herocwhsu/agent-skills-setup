#!/usr/bin/env python3
"""LLM-backed polish engine.

AuthProvider subclasses supply credentials; polish() tries each in order and
returns the first successful rewrite. Callers build the provider list based on
the detected agent context (see polish.py).
"""

from __future__ import annotations

import base64
import datetime
import hashlib
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


def _read_antigravity_keychain_value() -> str | None:
    """Read the raw Antigravity CLI session blob from the OS keyring.

    Antigravity CLI (agy) replaced the legacy Gemini CLI and stores its
    Google OAuth session via a Go keyring library under
    service="gemini", account="antigravity" — macOS Keychain or Linux
    Secret Service depending on platform. The stored value is prefixed
    "go-keyring-base64:" followed by base64-encoded JSON:
    {"auth_method": ..., "token": {"access_token", "refresh_token",
    "token_type", "expiry"}}.
    """
    try:
        r = subprocess.run(
            ["security", "find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"],
            capture_output=True,
            text=True,
        )
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except FileNotFoundError:
        pass

    try:
        r = subprocess.run(
            ["secret-tool", "lookup", "service", "gemini", "username", "antigravity"],
            capture_output=True,
            text=True,
        )
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except FileNotFoundError:
        pass

    return None


class GeminiAntigravityProvider(AuthProvider):
    """OAuth credentials from the active Antigravity CLI (agy) session.

    Only the raw access_token is used — Antigravity's OAuth client_id is
    not something we can reliably assume, so we don't attempt a refresh.
    An expired token is treated as "no credential" (falls through to the
    next provider) rather than risking a failed refresh call.
    """

    name = "gemini-antigravity"
    backend = "gemini"
    cred_type = "oauth"

    def credential(self) -> Any:
        raw = _read_antigravity_keychain_value()
        if not raw:
            return None
        try:
            import google.oauth2.credentials

            payload = raw
            prefix = "go-keyring-base64:"
            if payload.startswith(prefix):
                payload = payload[len(prefix) :]
            decoded = base64.b64decode(payload + "=" * (-len(payload) % 4))
            data = json.loads(decoded)
            token = data.get("token", {})
            access_token = token.get("access_token")
            if not access_token:
                return None
            expiry = token.get("expiry")
            if expiry:
                exp_dt = datetime.datetime.fromisoformat(expiry)
                if exp_dt.tzinfo is None:
                    exp_dt = exp_dt.replace(tzinfo=datetime.timezone.utc)
                if datetime.datetime.now(datetime.timezone.utc) >= exp_dt:
                    return None
            return google.oauth2.credentials.Credentials(token=access_token)
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
                    [
                        "secret-tool",
                        "lookup",
                        "service",
                        "agent-skills-setup:gemini",
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
            system=[
                {"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}
            ],
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
        model = genai.GenerativeModel(
            model_name="gemini-1.5-flash", system_instruction=SYSTEM_PROMPT
        )
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
