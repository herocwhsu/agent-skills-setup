---
subcommand: draft
group: sre-migration
slash: /sre-migration-draft <STORY-ID>
output: ./docs/stories/<STORY-ID>-<slug>/migration-ticket.md, command-flow.md
---

# sre-migration/draft — Draft the ticket body and command flow

Reads the ticket template, then writes the ticket body and the per-environment
execution commands.

## Overview

Two outputs, both Chinese, both in the story folder:

- `migration-ticket.md` — the ticket body, section-for-section against the
  template.
- `command-flow.md` — the actual commands per environment. A ticket filed
  without these is what happened once already, and the steps had to be written
  by hand afterwards.

The skill's own files stay English; these two deliverables are Chinese because
that is what the SRE reviewer reads.

## Steps

### Step 1 — Resolve the template, story folder first

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1

STORY_ID="$1"
STORY_DIR=$(find ./docs/stories -maxdepth 1 -type d -name "${STORY_ID}-*" | head -1)
[[ -n "$STORY_DIR" ]] || { echo "ERROR: no story folder for $STORY_ID" >&2; exit 1; }

TEMPLATE=$(find "$STORY_DIR" .. -maxdepth 3 -name 'confluence-*migration-ticket*.md' 2>/dev/null | head -1)
```

If found, use it and report which file and which `Source:` line it came from.
The guide is a checked-in artifact — 381 lines, carrying its own source URL —
so this path needs no network and no credential.

If absent, fetch it, then **write it into the story folder** so the next
subcommand and the next story reuse it:

```bash
# The guide is Cloud-hosted under the Jira site host at /wiki, and answers to
# the Jira credential. $CONFLUENCE_HOST is self-hosted, internal-DNS-only, and
# serves different pages — sending a Cloud page id there fails to resolve.
PAGE_URL="<the wiki URL named in the story>"
PAGE_HOST=$(printf '%s' "$PAGE_URL" | sed -E 's|^https?://([^/]+)/.*|\1|')
PAGE_ID=$(printf '%s' "$PAGE_URL" | sed -E 's|.*/pages/([0-9]+).*|\1|')

if [[ "$PAGE_HOST" == "$JIRA_HOST" ]]; then
  SLUG=$(service_slug jira "https://$JIRA_HOST")
  _PASS=$(require_secret "$SLUG" "$JIRA_USER" "bash scripts/credentials/service.sh jira add") || exit 1
  curl -s -u "$JIRA_USER:$_PASS" \
    "https://$JIRA_HOST/wiki/rest/api/content/$PAGE_ID?expand=body.storage,title" \
    > /tmp/_tmpl.json
  unset _PASS
else
  CONF_SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
  _PASS=$(require_secret "$CONF_SLUG" "$CONFLUENCE_USER" "bash scripts/credentials/service.sh confluence add") || exit 1
  curl -s -u "$CONFLUENCE_USER:$_PASS" \
    "https://$CONFLUENCE_HOST/rest/api/content/$PAGE_ID?expand=body.storage,title" \
    > /tmp/_tmpl.json
  unset _PASS
fi
```

### Step 2 — Draft `migration-ticket.md`

Follow the template's own section list, read from the artifact rather than
hardcoded here:

| Section | Content |
|---|---|
| 變更說明 | Purpose and what this change does |
| 程式碼位置 | Repo / Branch or Tag / **Commit SHA** / Path |
| 目標資源/資料表 | Each resource by type and name; Database / Table for RDS |
| 是否提供 Rollback | Yes/No, with the irreversibility reason when No |
| 涉及 PII/機敏資料 | Yes/No/不確定 plus the data types. 不確定 is a valid answer, deferred to SRE |
| 執行時機 | Before/after a deploy, or unrelated to one |
| 各操作說明 | All six operations × 是否提供 / 說明 / 可否重複執行 |
| precheck 輸出 (Dev) | Real dev output, including affected row count |
| 所需權限申請 | The policy the tool needs |

The three `SRE *` record fields are **not** body sections. They are separate
Jira custom fields, left for SRE to fill.

### Step 3 — Draft `command-flow.md`

One block per environment the tool accepts, each showing the full ordered
sequence with the real items file for that environment.

`--yes` may appear for dev and stage automation. **Never for prod** — the typed
confirmation is the last gate before a production write.

Because the operator has no stage or prod VPN, those blocks are prepared *for
SRE to run*. Say so in the document; never present them as something already run.

## Common Mistakes

| Mistake | Why it matters |
|---|---|
| Re-fetching when the story folder already has the guide | Duplicates intake, needs credentials, and can drift from what the story was written against |
| Sending a Cloud page id to `$CONFLUENCE_HOST` | Different host, different pages; it will not resolve |
| Rendering the three SRE record fields as `##` headings | They are Jira fields; SRE cannot fill a body heading |
| Leaving a 說明 empty | Exactly what got a filed ticket sent back |
| `--yes` in a prod block | Removes the last confirmation before a production write |
| Presenting a prod command as executed | The operator cannot reach prod; SRE runs it |
