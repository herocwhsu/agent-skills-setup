#!/usr/bin/env python3
"""Unit tests for cred_provider — Confluence credential provider hierarchy."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from unittest import mock

import pytest

LIB = Path(__file__).resolve().parents[1] / "lib"
sys.path.insert(0, str(LIB))


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    monkeypatch.delenv("CONFLUENCE_PASS", raising=False)


# ---------------------------------------------------------------------------
# ConfluenceEnvProvider
# ---------------------------------------------------------------------------

def test_env_provider_reads_env_var(monkeypatch):
    monkeypatch.setenv("CONFLUENCE_PASS", "secret123")
    import cred_provider
    assert cred_provider.ConfluenceEnvProvider().credential() == "secret123"


def test_env_provider_returns_none_when_unset():
    import cred_provider
    assert cred_provider.ConfluenceEnvProvider().credential() is None


def test_env_provider_returns_none_for_empty_string(monkeypatch):
    monkeypatch.setenv("CONFLUENCE_PASS", "")
    import cred_provider
    assert cred_provider.ConfluenceEnvProvider().credential() is None


# ---------------------------------------------------------------------------
# ConfluenceConfigKeychainProvider — file fallback (pure Python, no subprocess)
# ---------------------------------------------------------------------------

def test_keychain_provider_reads_from_credentials_json(tmp_path, monkeypatch):
    import cred_provider
    creds_file = tmp_path / "credentials.json"
    svc = "agent-skills-setup:confluence-https-example-com"
    creds_file.write_text(json.dumps({f"{svc}:testuser": "kc-pass"}))
    monkeypatch.setattr(cred_provider, "_FALLBACK_STORE", str(creds_file))
    # skip subprocess by making both platform commands raise FileNotFoundError
    monkeypatch.setattr(
        cred_provider.subprocess, "run",
        mock.Mock(side_effect=FileNotFoundError()),
    )
    p = cred_provider.ConfluenceConfigKeychainProvider("https://example.com", "testuser")
    assert p.credential() == "kc-pass"


def test_keychain_provider_returns_none_when_file_missing(tmp_path, monkeypatch):
    import cred_provider
    monkeypatch.setattr(cred_provider, "_FALLBACK_STORE", str(tmp_path / "no.json"))
    monkeypatch.setattr(
        cred_provider.subprocess, "run",
        mock.Mock(side_effect=FileNotFoundError()),
    )
    p = cred_provider.ConfluenceConfigKeychainProvider("https://example.com", "user")
    assert p.credential() is None


def test_keychain_provider_returns_none_when_key_missing(tmp_path, monkeypatch):
    import cred_provider
    creds_file = tmp_path / "credentials.json"
    creds_file.write_text(json.dumps({"unrelated:user": "other"}))
    monkeypatch.setattr(cred_provider, "_FALLBACK_STORE", str(creds_file))
    monkeypatch.setattr(
        cred_provider.subprocess, "run",
        mock.Mock(side_effect=FileNotFoundError()),
    )
    p = cred_provider.ConfluenceConfigKeychainProvider("https://example.com", "user")
    assert p.credential() is None


# ---------------------------------------------------------------------------
# resolve_credential cascade
# ---------------------------------------------------------------------------

def test_resolve_credential_uses_env_first(monkeypatch, tmp_path):
    monkeypatch.setenv("CONFLUENCE_PASS", "env-pass")
    import cred_provider
    monkeypatch.setattr(cred_provider, "_FALLBACK_STORE", str(tmp_path / "no.json"))
    assert cred_provider.resolve_credential("https://example.com", "user") == "env-pass"


def test_resolve_credential_falls_through_to_keychain(monkeypatch, tmp_path):
    import cred_provider
    creds_file = tmp_path / "credentials.json"
    svc = "agent-skills-setup:confluence-https-example-com"
    creds_file.write_text(json.dumps({f"{svc}:user": "kc-pass"}))
    monkeypatch.setattr(cred_provider, "_FALLBACK_STORE", str(creds_file))
    monkeypatch.setattr(
        cred_provider.subprocess, "run",
        mock.Mock(side_effect=FileNotFoundError()),
    )
    assert cred_provider.resolve_credential("https://example.com", "user") == "kc-pass"


def test_resolve_credential_returns_none_when_all_fail(monkeypatch, tmp_path):
    import cred_provider
    monkeypatch.setattr(cred_provider, "_FALLBACK_STORE", str(tmp_path / "no.json"))
    monkeypatch.setattr(
        cred_provider.subprocess, "run",
        mock.Mock(side_effect=FileNotFoundError()),
    )
    assert cred_provider.resolve_credential("https://example.com", "user") is None


# ---------------------------------------------------------------------------
# Slug helpers
# ---------------------------------------------------------------------------

def test_slugify_url():
    import cred_provider
    assert cred_provider._slugify_url("https://example.com") == "https-example-com"


def test_service_slug():
    import cred_provider
    slug = cred_provider._service_slug("confluence", "https://example.com")
    assert slug == "confluence-https-example-com"


def test_bare_host_gets_https_prefix():
    import cred_provider
    p = cred_provider.ConfluenceConfigKeychainProvider("example.com", "user")
    assert "https-example-com" in p._svc_key
