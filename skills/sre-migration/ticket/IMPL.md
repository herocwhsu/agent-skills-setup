---
subcommand: ticket
group: sre-migration
slash: /sre-migration-ticket <STORY-ID>
output: Jira issue key
---

# sre-migration/ticket — File the SRE issue

Creates the `Change Request - Migration Execution` issue from a linted draft.

## Overview

Run this only after `/sre-migration-lint` is clean and a human has made the
high-risk call. Filing an unlinted draft is what this skill exists to prevent.

## Steps

### Step 1 — Refuse to file an unlinted draft

Re-run lint and stop on any failure. The gate is worthless if this step is
skipped when inconvenient.

### Step 2 — Resolve ids by name at runtime

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
SLUG=$(service_slug jira "https://$JIRA_HOST")
_PASS=$(require_secret "$SLUG" "$JIRA_USER" "bash scripts/credentials/service.sh jira add") || exit 1

# Resolve the SRE project's id from its key, then the issue type's id from its
# NAME. Never pin numeric ids in this file: they are site-specific, and a
# re-pointed site is exactly the failure this skill already hit once.
PROJECT_KEY="<the SRE project key>"
PROJECT_ID=$(curl -s -u "$JIRA_USER:$_PASS" \
  "https://$JIRA_HOST/rest/api/3/project/$PROJECT_KEY" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

# maxResults matters: the default page cut the list off mid-way and made the
# type look absent when it was merely on a later page.
curl -s -u "$JIRA_USER:$_PASS" \
  "https://$JIRA_HOST/rest/api/3/issue/createmeta/$PROJECT_ID/issuetypes?startAt=0&maxResults=100" \
  > /tmp/_types.json
ISSUE_TYPE_ID=$(python3 -c '
import json
d = json.load(open("/tmp/_types.json"))
for t in d.get("issueTypes", []):
    if t["name"] == "Change Request - Migration Execution":
        print(t["id"]); break
')
```

### Step 3 — Resolve the required fields, also by name

```bash
curl -s -u "$JIRA_USER:$_PASS" \
  "https://$JIRA_HOST/rest/api/3/issue/createmeta/$PROJECT_ID/issuetypes/$ISSUE_TYPE_ID?maxResults=100" \
  > /tmp/_fields.json
unset _PASS
```

Required: `project`, `summary`, and **Platform Service** — a custom field whose
value is an option (VORTEX / RESELLER / VORTEXAI). Resolve its field id by
matching the field *name*, not by pinning the id. Description is optional.

### Step 4 — Set the three SRE record fields as fields, and leave them empty

`SRE Pre-check`, `SRE Stage Record`, and `SRE Prod Record` are separate custom
fields that SRE fills. Resolve their ids by name and leave them empty. Do not
render them as `##` headings inside the Description — SRE cannot fill a body
heading, and existing drafts got this wrong.

### Step 5 — File it and report the key

Post the drafted `migration-ticket.md` body as the Description, then print the
returned issue key and its URL. Attach `command-flow.md` (or include it in the
body) so the reviewer has the commands.

## Common Mistakes

| Mistake | Why it matters |
|---|---|
| Filing without a clean lint | Defeats the purpose of the gate |
| Pinning numeric project / issue-type / custom-field ids | Site-specific and brittle; resolve by name |
| Omitting `maxResults=100` on createmeta | Default paging hides the type and reads as "not creatable" |
| Putting the SRE record fields in the body | They are Jira fields; SRE cannot fill a heading |
| Filing before the high-risk call is made | It may need a management sign-off first |
