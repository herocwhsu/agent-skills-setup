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

```bash
bash scripts/credentials/service.sh confluence add

# Verify (no value printed):
bash scripts/credentials/service.sh confluence verify
```

The setup writes both the keychain entry and `CONFLUENCE_HOST` /
`CONFLUENCE_USER` keys in `~/.agent-skills-setup/config.sh`.

## Implementation

### Step 0 — Load config and helpers

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
```

### Confluence URL (REST API path)

```bash
[[ -z "${CONFLUENCE_HOST:-}" ]] && { echo "ERROR: CONFLUENCE_HOST not in config.sh — run: bash scripts/credentials/service.sh confluence add" >&2; exit 1; }

SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
_PASS=$(require_secret "$SLUG" "$CONFLUENCE_USER" "bash scripts/credentials/service.sh confluence add") || exit 1

SPACE="PP2"
TITLE="My Page Title"
API="https://$CONFLUENCE_HOST/rest/api/content"

# Use temp file — avoids shell variable corruption of HTML content (pipes, special chars, tables)
curl -s -u "$CONFLUENCE_USER:$_PASS" \
  "${API}?spaceKey=${SPACE}&title=${TITLE}&expand=body.storage" \
  > /tmp/_cf_response.json
unset _PASS

HTML2MD=$(find_html2md) || exit 1

python3 - <<EOF
import json, subprocess, os, re
from datetime import date

with open('/tmp/_cf_response.json') as f:
    data = json.load(f)

r = data['results'][0]
title = r['title']
html = r['body']['storage']['value']

with open('/tmp/_cf_body.html', 'w') as f:
    f.write(html)

slug = re.sub(r'-+', '-', re.sub(r'[^a-z0-9]', '-', title.lower()))[:40]
out_dir = './docs/pre-specs'
os.makedirs(out_dir, exist_ok=True)
out = f"{out_dir}/{date.today()}-{slug}-reference.md"

result = subprocess.run(
    ['python3', '$HTML2MD'],
    stdin=open('/tmp/_cf_body.html'), capture_output=True, text=True
)
with open(out, 'w') as f:
    f.write(result.stdout)

print(f"Saved: {out}")
EOF
rm -f /tmp/_cf_response.json /tmp/_cf_body.html
```

### MCP path (if Confluence MCP server configured)

If a Confluence MCP tool is available, use it instead — it handles auth and returns clean content directly. Still save output with the same file naming convention.

### Non-Confluence URL (plain curl)

```bash
URL="https://example.com/some-page"
SLUG=$(slugify_url "$URL" | cut -c1-40)
DATE=$(date +%Y-%m-%d)
HTML2MD=$(find_html2md) || exit 1

mkdir -p ./docs/pre-specs
curl -s "$URL" | python3 "$HTML2MD" \
  > "./docs/pre-specs/${DATE}-${SLUG}-reference.md"
```

For authenticated non-Confluence URLs, call `require_secret <slug> <user>`
against the appropriate slug — see fetch-jira-story's Apidog example.

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
| `lib.sh: No such file or directory` | Run `bash scripts/install.sh` first |
| `CONFLUENCE_HOST not in config.sh` | Run `bash scripts/credentials/service.sh confluence add` |
| `echo "$HTML"` corrupts content | Use temp file (`/tmp/_cf_body.html`) — shell variables mangle special chars and tables |
| Confluence returns XML, not HTML | Use REST API `body.storage` endpoint, not page URL |
| Tables lost | `html2md.py` handles `<table>` → markdown table |
| Output dir missing | `os.makedirs(out_dir, exist_ok=True)` before writing |
| Using Confluence MCP for non-Confluence URL | Use plain curl for any non-Confluence URL |
