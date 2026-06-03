#!/usr/bin/env python3
"""Confluence credential provider hierarchy.

CredentialProvider subclasses resolve a Confluence password/PAT from
different sources. resolve_credential() tries each in order, returning
the first non-None result.

Mirrors the AuthProvider pattern in polish_engine.py.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

_KEYCHAIN_PREFIX = "agent-skills-setup"
_FALLBACK_STORE = "~/.agent-skills-setup/credentials.json"


def _slugify_url(url: str) -> str:
    """Convert a URL to a keychain-safe slug. Mirrors lib/lib.sh:slugify_url."""
    s = re.sub(r"[^a-zA-Z0-9]", "-", url)
    s = re.sub(r"-+", "-", s)
    return s.strip("-")


def _service_slug(prefix: str, url: str) -> str:
    """Compose a service-prefixed slug. Mirrors lib/lib.sh:service_slug."""
    return f"{prefix}-{_slugify_url(url)}"


class ConfluenceCredentialProvider:
    """Base class. Subclasses define name and credential()."""
    name: str

    def credential(self) -> str | None:
        raise NotImplementedError


class ConfluenceEnvProvider(ConfluenceCredentialProvider):
    """Read CONFLUENCE_PASS from the environment (backward-compatible).

    Stateless: ignores host and user. If multiple Confluence instances are
    configured in the same process, the env var wins regardless of which
    host resolve_credential() was called with — set CONFLUENCE_PASS
    explicitly to the correct value in that case.
    """
    name = "env"

    def credential(self) -> str | None:
        return os.environ.get("CONFLUENCE_PASS") or None


class ConfluenceConfigKeychainProvider(ConfluenceCredentialProvider):
    """Read password/PAT from the agent-skills-setup platform keychain.

    Replicates the bash workflow in the confluence SKILL.md:
        SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
        _PASS=$(require_secret "$SLUG" "$CONFLUENCE_USER")
    """
    name = "keychain"

    def __init__(self, host: str, user: str) -> None:
        base_url = host if host.startswith(("http://", "https://")) else f"https://{host}"
        self._slug = _service_slug("confluence", base_url)
        self._svc_key = f"{_KEYCHAIN_PREFIX}:{self._slug}"
        self._user = user

    def credential(self) -> str | None:
        # Try macOS Keychain
        try:
            r = subprocess.run(
                ["security", "find-generic-password",
                 "-s", self._svc_key, "-a", self._user, "-w"],
                capture_output=True, text=True,
            )
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
        except FileNotFoundError:
            pass

        # Try Linux secret-tool
        try:
            r = subprocess.run(
                ["secret-tool", "lookup",
                 "service", self._svc_key, "username", self._user],
                capture_output=True, text=True,
            )
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
        except FileNotFoundError:
            pass

        # Fall back to credentials.json (headless / CI)
        return self._from_file()

    def _from_file(self) -> str | None:
        fb = Path(os.path.expanduser(_FALLBACK_STORE))
        if not fb.exists():
            return None
        try:
            data = json.loads(fb.read_text())
            return data.get(f"{self._svc_key}:{self._user}") or None
        except Exception:
            return None


def resolve_credential(host: str, user: str) -> str | None:
    """Try providers in priority order; return first non-None credential."""
    for p in [ConfluenceEnvProvider(), ConfluenceConfigKeychainProvider(host, user)]:
        cred = p.credential()
        if cred is not None:
            return cred
    return None
