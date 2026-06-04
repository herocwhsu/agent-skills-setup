---
name: fetch-jira-story
description: Use when given a Jira story ID or URL to fetch story details and save as markdown reference files. Follows embedded Confluence and Apidog links automatically. Requires Jira credentials in keychain.
---

# Fetch Jira Story

## Overview

Fetch a Jira story and all linked reference pages, save to `./docs/stories/<STORY-ID>/`.

## Output Structure

```
./docs/stories/<STORY-ID>/
  story.md              ← story description + extracted links list
  confluence-<slug>.md  ← one file per Confluence link (via fetch-page-to-markdown)
  apidog-<slug>.md      ← one file per Apidog/public link (plain curl)
```

## Credential Setup

Run once per service. The setup writes both the keychain entry and the
matching `config.sh` keys (`JIRA_HOST`, `JIRA_USER`, `JIRA_PROJECT_KEY`).

```bash
bash scripts/credentials/service.sh jira add

# Verify (no value printed):
bash scripts/credentials/service.sh jira verify
```

**Important:** Jira Cloud requires the full email address as the username. Username-only returns 401.

## Implementation

### Step 0 — Load config and helpers

Every skill invocation starts with this:

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1

# Validate required keys are set
[[ -z "${JIRA_HOST:-}" ]] && { echo "ERROR: JIRA_HOST not in config.sh — run: bash scripts/credentials/service.sh jira add" >&2; exit 1; }
[[ -z "${JIRA_USER:-}" ]] && { echo "ERROR: JIRA_USER not in config.sh — run: bash scripts/credentials/service.sh jira add" >&2; exit 1; }
```

### Step 1 — Fetch story

```bash
STORY_ID="$1"   # e.g. PROJ-123

SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER" "bash scripts/credentials/service.sh jira add") || exit 1

curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$STORY_ID" \
  > /tmp/_jira_issue.json
unset _JIRA_PASS
```

### Step 2 — Extract and save story.md

```python
import json, re, os

with open('/tmp/_jira_issue.json') as f:
    issue = json.load(f)

fields = issue['fields']
story_id = issue['key']
title = fields['summary']
description = fields.get('description') or ''
status = fields['status']['name']
story_type = fields['issuetype']['name']

out_dir = f'./docs/stories/{story_id}'
os.makedirs(out_dir, exist_ok=True)

urls = re.findall(r'https?://[^\s\|\]\"]+', description)

with open(f'{out_dir}/story.md', 'w') as f:
    f.write(f'# {story_id}: {title}\n\n')
    f.write(f'**Type:** {story_type}  \n**Status:** {status}  \n**Branch:** {story_id}\n\n')
    f.write('## Description\n\n')
    f.write(description + '\n\n')
    if urls:
        f.write('## Extracted Links\n\n')
        for url in urls:
            f.write(f'- {url}\n')

print(f'Saved: {out_dir}/story.md')
print(f'Links found: {urls}')
```

### Step 3 — Follow links

For each extracted URL:

**Confluence links** (host matches `$CONFLUENCE_HOST`):

```bash
[[ -z "${CONFLUENCE_HOST:-}" ]] && { echo "ERROR: CONFLUENCE_HOST not in config.sh — skip Confluence link" >&2; }

CONF_SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
_CONF_PASS=$(require_secret "$CONF_SLUG" "$CONFLUENCE_USER" "bash scripts/credentials/service.sh confluence add")

if [[ -n "${_CONF_PASS:-}" ]]; then
  PAGE_ID="<extracted from URL ?pageId=XXXXXX>"
  HTML2MD=$(find_html2md) || exit 1

  curl -s -u "$CONFLUENCE_USER:$_CONF_PASS" \
    "https://$CONFLUENCE_HOST/rest/api/content/$PAGE_ID?expand=body.storage,title" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['body']['storage']['value'])
" | python3 "$HTML2MD" > "./docs/stories/$STORY_ID/confluence-${PAGE_ID}.md"
  unset _CONF_PASS
fi
```

→ Save to `./docs/stories/<STORY-ID>/confluence-<pageId>.md`

**Apidog / other public links**:

```bash
URL="https://..."
SLUG=$(slugify_url "$URL" | cut -c1-40)
HTML2MD=$(find_html2md) || exit 1

curl -s "$URL" | python3 "$HTML2MD" \
  > "./docs/stories/$STORY_ID/apidog-${SLUG}.md"
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| `lib.sh: No such file or directory` | Run `bash scripts/install.sh` first |
| `JIRA_HOST not in config.sh` | Run `bash scripts/credentials/service.sh jira add` |
| Wrong slug | Slug is `service_slug jira "https://$JIRA_HOST"` — check with `bash scripts/credentials/service.sh jira list` |
| Description is Jira wiki markup, not plain text | Strip `{code}`, `*bold*`, `[link\|url]` patterns before saving |
| Links inside `[text\|url]` format missed | Use regex `\[([^\|]+)\|([^\]]+)\]` to extract Jira-format links too |
