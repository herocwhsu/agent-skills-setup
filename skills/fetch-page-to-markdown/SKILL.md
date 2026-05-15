---
name: fetch-page-to-markdown
description: Use when given one or more web URLs to fetch and save as markdown reference files, with optional auth. Handles Confluence REST API, internal wikis, or any authenticated web page. Multi-platform credential storage (macOS Keychain, Linux secret-tool, Windows Credential Manager, CI env vars).
---

# Fetch Page to Markdown

## Overview

Fetch one or more web pages and save as `YYYY-MM-DD-<slug>-reference.md` in `./docs/pre-specs/`. Supports Basic Auth via platform keychain. Never echo passwords.

## URL Decision

```
Is the URL a Confluence instance?
├── Yes → Use Confluence REST API (structured, clean body)
│         Prefer MCP if confluence MCP server is configured
│         Fallback: curl + REST API
└── No  → Use plain curl (works for any URL)
          Add -u flag only if auth is required
```

## Credential Setup (one-time per platform)

**macOS — Keychain:**
```bash
security add-generic-password -s confluence-example-org -a <user> -w
# prompts securely, no echo
```

**Linux (GNOME/KDE) — libsecret:**
```bash
secret-tool store --label="Confluence" service confluence-example-org username <user>
```

**Linux headless / CI — env var directly:**
```bash
export CONFLUENCE_PASS="your-password"   # inject via CI secret, not hardcoded
```

**Windows — Credential Manager:**
```powershell
cmdkey /add:confluence-example-org /user:<user> /pass
# or via GUI: Control Panel > Credential Manager > Windows Credentials
```

## Shell Profile Setup

Add to `~/.zshrc` or `~/.bashrc` so `$CONFLUENCE_PASS` is always available:

```bash
if [[ "$(uname)" == "Darwin" ]]; then
  export CONFLUENCE_PASS=$(security find-generic-password -s confluence-example-org -a <user> -w 2>/dev/null)
elif command -v secret-tool &>/dev/null; then
  export CONFLUENCE_PASS=$(secret-tool lookup service confluence-example-org username <user> 2>/dev/null)
fi
# Linux headless/CI: set CONFLUENCE_PASS via pipeline secret injection
# Windows: read via PowerShell before invoking kiro
```

**Always validate before fetching:**
```bash
if [ -z "$CONFLUENCE_PASS" ]; then
  echo "ERROR: CONFLUENCE_PASS is not set. Run credential setup first." >&2
  exit 1
fi
```

## Security Rule

**Never put the password in command text.** Tool call display shows the full command — any inline value is visible.

```bash
# ✅ GOOD
curl -s -u "<user>:$CONFLUENCE_PASS" "$URL"

# ❌ BAD — visible in logs
curl -s -u "<user>:plaintext" "$URL"
```

## Implementation

### Confluence URL (REST API path)

```bash
# Extract page body via REST API (returns clean XML storage format)
SPACE="PP2"
TITLE="My Page Title"
API="https://confluence.example.com/rest/api/content"

BODY=$(curl -s -u "<user>:$CONFLUENCE_PASS" \
  "${API}?spaceKey=${SPACE}&title=${TITLE}&expand=body.storage" | \
  python3 -c "import sys,json; r=json.load(sys.stdin)['results'][0]; print(r['title']+'|||'+r['body']['storage']['value'])")

TITLE=$(echo "$BODY" | cut -d'|' -f1)
HTML=$(echo "$BODY" | cut -d'|' -f4-)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | cut -c1-40)
DATE=$(date +%Y-%m-%d)

mkdir -p ./docs/pre-specs
echo "$HTML" | python3 ~/.kiro/skills/fetch-page-to-markdown/html2md.py \
  > "./docs/pre-specs/${DATE}-${SLUG}-reference.md"
echo "Saved: ./docs/pre-specs/${DATE}-${SLUG}-reference.md"
```

### MCP path (if Confluence MCP server configured)

If a Confluence MCP tool is available, use it instead — it handles auth and returns clean content directly. Still save output with the same file naming convention.

### Non-Confluence URL (plain curl)

```bash
URL="https://example.com/some-page"
SLUG=$(echo "$URL" | sed 's|.*://||' | sed 's/[^a-z0-9]/-/g' | cut -c1-40)
DATE=$(date +%Y-%m-%d)

mkdir -p ./docs/pre-specs
curl -s "$URL" | python3 ~/.kiro/skills/fetch-page-to-markdown/html2md.py \
  > "./docs/pre-specs/${DATE}-${SLUG}-reference.md"

# With auth (Basic Auth):
curl -s -u "user:$CONFLUENCE_PASS" "$URL" | python3 ~/.kiro/skills/fetch-page-to-markdown/html2md.py \
  > "./docs/pre-specs/${DATE}-${SLUG}-reference.md"
```

## File Naming

```
./docs/pre-specs/YYYY-MM-DD-<slug>-reference.md
```

- `YYYY-MM-DD` — today's date
- `<slug>` — page title (or URL) lowercased, non-alphanumeric → hyphens, max 40 chars
- Create output dir if missing: `mkdir -p ./docs/pre-specs`

## Multiple URLs

Process each URL independently. One file per URL. Report each saved path.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Password in command text | Use `$CONFLUENCE_PASS` variable only |
| `$CONFLUENCE_PASS` empty, silent 401 | Add empty-check before fetching |
| Confluence returns XML, not HTML | Use REST API `body.storage` endpoint, not page URL |
| Tables lost | `html2md.py` handles `<table>` → markdown table |
| Output dir missing | `mkdir -p ./docs/pre-specs` before writing |
| Using Confluence MCP for non-Confluence URL | Use plain curl for any non-Confluence URL |
