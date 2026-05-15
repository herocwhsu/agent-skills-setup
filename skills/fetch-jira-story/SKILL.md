---
name: fetch-jira-story
description: Use when given a Jira story ID or URL to fetch story details and save as markdown reference files. Follows embedded Confluence and Apidog links automatically. Requires Jira credentials in keychain.
---

# Fetch Jira Story

## Overview

Fetch a Jira story and all linked reference pages, save to `./docs/stories/<STORY-ID>/`.

## Output Structure

```
./docs/stories/VOR-29600/
  story.md              ← story description + extracted links list
  confluence-<slug>.md  ← one file per Confluence link (via fetch-page-to-markdown)
  apidog-<slug>.md      ← one file per Apidog/public link (plain curl)
```

## Credential Setup

Jira credentials are stored per-instance. Slug pattern: `jira-<host-with-dashes>`.

```bash
# Store (one-time):
bash ~/.kiro/skills/../../../agent-skills-setup/scripts/credentials/jira.sh add
# e.g. https://vivotek.atlassian.net → slug: jira-vivotek-atlassian-net

# Verify (safe — no value printed):
bash ~/.kiro/skills/../../../agent-skills-setup/scripts/credentials/jira.sh verify
```

## Security Rule

Read credential at use-time only. Unset immediately after. Never echo or export.

```bash
# ✅ GOOD
_JIRA_USER="hero.hsu"
_JIRA_PASS=$(security find-generic-password -s "agent-skills:jira-vivotek-atlassian-net" -a "$_JIRA_USER" -w 2>/dev/null)
curl -s -u "$_JIRA_USER:$_JIRA_PASS" "$URL" > /tmp/_jira.json
unset _JIRA_PASS
```

## Implementation

### Step 1 — Fetch story

```bash
STORY_ID="VOR-29600"   # from URL or argument
JIRA_HOST="vivotek.atlassian.net"
SLUG="jira-$(echo "$JIRA_HOST" | sed 's/[^a-zA-Z0-9]/-/g;s/-\+/-/g;s/-$//')"

_JIRA_USER=$(security find-generic-password -s "agent-skills:$SLUG" -a "" -w 2>/dev/null | head -1)
# Note: username stored separately — prompt if not known
read -rp "Jira username (email): " _JIRA_USER
_JIRA_PASS=$(security find-generic-password -s "agent-skills:$SLUG" -a "$_JIRA_USER" -w 2>/dev/null)

if [ -z "$_JIRA_PASS" ]; then
  echo "ERROR: Jira credential not found. Run: bash scripts/credentials/jira.sh add" >&2
  exit 1
fi

curl -s -u "$_JIRA_USER:$_JIRA_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$STORY_ID" \
  > /tmp/_jira_issue.json
unset _JIRA_PASS
```

### Step 2 — Extract and save story.md

```python
import json, re, os
from datetime import date

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

# Extract URLs from description
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

**Confluence links** (`confluence.` in host):
→ Use fetch-page-to-markdown skill implementation (REST API path).
→ Save to `./docs/stories/<STORY-ID>/confluence-<slug>.md`

**Apidog / other public links**:
```bash
URL="https://..."
SLUG=$(echo "$URL" | sed 's|.*://||;s/[^a-z0-9]/-/g' | cut -c1-40)
curl -s "$URL" | python3 ~/.kiro/skills/fetch-page-to-markdown/html2md.py \
  > "./docs/stories/$STORY_ID/apidog-${SLUG}.md"
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Username not in keychain | Prompt for username; pass to `security find-generic-password -a` |
| Wrong JIRA_HOST slug | Check with `bash jira.sh list` |
| Description is Jira wiki markup, not plain text | Strip `{code}`, `*bold*`, `[link\|url]` patterns before saving |
| Links inside `[text\|url]` format missed | Use regex `\[([^\|]+)\|([^\]]+)\]` to extract Jira-format links too |
