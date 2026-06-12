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

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1

# Validate required keys are set
[[ -z "${JIRA_HOST:-}" ]] && { echo "ERROR: JIRA_HOST not in config.sh — run: bash scripts/credentials/service.sh jira add" >&2; exit 1; }
[[ -z "${JIRA_USER:-}" ]] && { echo "ERROR: JIRA_USER not in config.sh — run: bash scripts/credentials/service.sh jira add" >&2; exit 1; }
```

### Step 1 — Fetch story

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1

STORY_ID="$1"   # e.g. PROJ-123

SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER" "bash scripts/credentials/service.sh jira add") || exit 1

curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$STORY_ID" \
  > /tmp/_jira_issue.json
unset _JIRA_PASS
```

### Step 2 — Extract and save story.md

**Important:** Jira wiki markup uses `[text|url|smart-link]` and `[text|url]` formats.
The plain-URL regex must stop at `|` to avoid capturing `|smart-link` as part of the URL.
Use `dict.fromkeys` to deduplicate while preserving order.

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
assignee = (fields.get('assignee') or {}).get('displayName', 'Unassigned')
reporter = (fields.get('reporter') or {}).get('displayName', 'Unknown')
priority = (fields.get('priority') or {}).get('name', 'Unknown')

# slug from title (lowercase, alphanumeric + dashes, max 50 chars)
slug = re.sub(r'[^a-z0-9]+', '-', title.lower())[:50].strip('-')
out_dir = f'./docs/stories/{story_id}-{slug}'
os.makedirs(out_dir, exist_ok=True)

# Extract URLs — two patterns:
# 1. Plain URLs: stop at whitespace, |, ], "
# 2. Jira wiki [text|url] and [text|url|smart-link]: capture the URL segment between first and second |
plain_urls = re.findall(r'https?://[^\s\|\]\"\}]+', description)
wiki_urls  = re.findall(r'\[[^\|]*\|(https?://[^\|\]]+)', description)
all_urls   = list(dict.fromkeys(plain_urls + wiki_urls))  # dedup, preserve order

with open(f'{out_dir}/story.md', 'w') as f:
    f.write(f'# {story_id}: {title}\n\n')
    f.write(f'**Type:** {story_type}  \n')
    f.write(f'**Status:** {status}  \n')
    f.write(f'**Priority:** {priority}  \n')
    f.write(f'**Assignee:** {assignee}  \n')
    f.write(f'**Reporter:** {reporter}  \n')
    f.write(f'**Branch:** {story_id}\n\n')
    f.write('## Description\n\n')
    f.write(description + '\n\n')
    if all_urls:
        f.write('## Extracted Links\n\n')
        for url in all_urls:
            f.write(f'- {url}\n')

print(f'Saved: {out_dir}/story.md')
print(f'Links found ({len(all_urls)}):')
for u in all_urls:
    print(f'  {u}')
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
