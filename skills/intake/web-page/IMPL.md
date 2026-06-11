---
name: fetch-page-to-markdown
description: Use when given one or more web URLs to fetch and save as markdown reference files, with optional auth. Handles Confluence REST API, internal wikis, or any authenticated web page. Multi-platform credential storage (macOS Keychain, Linux secret-tool, Windows Credential Manager, CI env vars).
---

# Fetch Page to Markdown

## Overview

Fetch one or more web pages and save as `YYYY-MM-DD-<slug>-reference.md` in `./docs/pre-specs/`. Supports Basic Auth via platform keychain. Never echo passwords.

## URL Decision

```
Is the URL share.apidog.com/<uuid>?
├── Yes → Use Apidog Share REST API (not WebFetch — JS SPA, returns blank)
│         ├── Try public (no password): GET https://api.apidog.com/v1/shared-docs/<uuid>/export-openapi
│         ├── If 401/403 → prompt user for share password, retry with
│         │   X-Apidog-Share-Password: <password> header
│         └── Parse returned OpenAPI JSON directly — no html2md needed
Is the URL app.apidog.com/project/<id>?
└── Yes → Use MCP apidog_export(module: ...) — requires token via MCP setup
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

### Apidog Share URL (`share.apidog.com/<uuid>`)

Extract the UUID from the URL and call the share export endpoint:

```bash
UUID=$(echo "$URL" | grep -oE '[0-9a-f-]{36}')
SHARE_API="https://api.apidog.com/v1/shared-docs/${UUID}/export-openapi"

HTTP_CODE=$(curl -s -o /tmp/_apidog_share.json -w "%{http_code}" "$SHARE_API")

if [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
  # Password-protected share — prompt user
  echo "This Apidog share link is password-protected."
  printf "Enter share password: "
  read -r SHARE_PASS
  HTTP_CODE=$(curl -s -o /tmp/_apidog_share.json -w "%{http_code}" \
    -H "X-Apidog-Share-Password: $SHARE_PASS" "$SHARE_API")
  unset SHARE_PASS
fi

[[ "$HTTP_CODE" != "200" ]] && {
  echo "ERROR: Apidog share export returned HTTP $HTTP_CODE" >&2
  cat /tmp/_apidog_share.json >&2
  rm -f /tmp/_apidog_share.json
  exit 1
}
```

The response is an OpenAPI 3.0 JSON spec. Save it directly — no html2md needed:

```bash
DATE=$(date +%Y-%m-%d)
SLUG=$(echo "$URL" | grep -oE '[0-9a-f-]{36}' | cut -c1-12)
OUT="./docs/pre-specs/${DATE}-apidog-${SLUG}-reference.json"
mkdir -p ./docs/pre-specs
mv /tmp/_apidog_share.json "$OUT"
echo "Saved: $OUT"
```

### Apidog App URL (`app.apidog.com/project/<id>`)

Use MCP — requires token configured via `/infra-apidog-mcp setup`:

```
apidog_export(module: <module-name>)
```

Save the returned OpenAPI spec to `./docs/pre-specs/${DATE}-apidog-<slug>-reference.json`.
If MCP is not configured, tell the user to run `/infra-apidog-mcp setup` first.

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
