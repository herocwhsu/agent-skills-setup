---
name: confluence
description: Use when the user wants to fetch, edit, create, or attach files to a self-hosted Confluence page. Round-trips macros and images via a sidecar `.meta.json`. Run from any directory; pages are saved under `./docs/confluence/`. Argument is a page ID, page URL, or a markdown file path (for update/create).
---

# confluence

Read and write **self-hosted Confluence Server/DC** pages from a markdown
file plus a sidecar `meta.json` that preserves macros, images, and
cross-page links.

> **Status: scaffolding.** The XHTML round-trip codec
> (`lib/storage_codec.py`) is a stub pending real-page fixtures from the
> target instance. The HTTP layer (push, attach) is implemented and
> testable in isolation. See `tests/fixtures/README.md` for the fixtures
> required before this skill is usable end-to-end.

## Subcommands

| Command | What it does |
|---|---|
| `/confluence-fetch <page-id-or-url>` | Save `<date>-<slug>.md` + `<date>-<slug>.meta.json` to `./docs/confluence/` |
| `/confluence-update <md-file>` | Read sibling `.meta.json`, re-emit XHTML, PUT with version bump (or abort on conflict) |
| `/confluence-create <md-file> --space <KEY> --parent <id>` | Create a new page from markdown only (no meta.json input) |

## The .meta.json contract

Sidecar file written next to each fetched page. **Never edit by hand.**

```json
{
  "pageId": "12345678",
  "version": 12,
  "space": "PP2",
  "ancestor": "23456789",
  "title": "My Page Title",
  "host": "confluence.example.com",
  "anchors": {
    "m1": { "type": "macro", "xml": "<ac:structured-macro ...>...</ac:structured-macro>" },
    "img1": { "type": "image", "filename": "diagram.png", "xml": "<ac:image>...</ac:image>" },
    "link1": { "type": "page-link", "xml": "<ac:link><ri:page .../></ac:link>" }
  }
}
```

In the markdown, anchors appear as:

```
<!-- ac:macro id="m1" -->
![diagram.png alt][ri:img1]
[Page title][ri:link1]
```

You can reorder, duplicate, or delete an anchor. You **cannot edit** what
it points to from this skill — open the page in Confluence's editor for
that.

## Auth

Reads `CONFLUENCE_HOST` and `CONFLUENCE_USER` from
`~/.agent-skills-setup/config.sh`; reads the password/token from the
keychain via `require_secret`.

- **Default:** Basic Auth (`username:password`).
- **PAT:** if the credential value matches PAT format
  (`[A-Za-z0-9_=-]{30,}` and contains no `:`), the skill switches to
  `Authorization: Bearer <token>` automatically. No credential-store
  change needed.

## Workflow: fetch

The argument is either a numeric page ID, a page URL, or a `space:title` pair.

### Step 1 — Load config

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
[[ -z "${CONFLUENCE_HOST:-}" ]] && { echo "ERROR: CONFLUENCE_HOST not in config.sh — run: bash scripts/credentials/service.sh confluence add" >&2; exit 1; }
```

### Step 2 — Try MCP first

If the agent has a Confluence MCP tool registered (e.g.
`confluence_get_page` from sooperset/mcp-atlassian), call it with the
page ID. The MCP server handles auth and returns
`{ id, title, version, space, ancestors, body.storage.value }`. Skip
to Step 4.

### Step 3 — REST fallback

```bash
SKILL_DIR=$(dirname "$0")
PAGE_ID="$1"   # extract from URL if needed
SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
_PASS=$(require_secret "$SLUG" "$CONFLUENCE_USER" "bash scripts/credentials/service.sh confluence add") || exit 1

curl -fsS -u "$CONFLUENCE_USER:$_PASS" \
  "https://$CONFLUENCE_HOST/rest/api/content/$PAGE_ID?expand=body.storage,version,space,ancestors" \
  > /tmp/_cf_page.json
unset _PASS
```

### Step 4 — Decode XHTML to md + meta.json

```bash
python3 "$SKILL_DIR/lib/storage_codec.py" decode \
  --input /tmp/_cf_page.json \
  --out-md ./docs/confluence/<date>-<slug>.md \
  --out-meta ./docs/confluence/<date>-<slug>.meta.json
```

`<slug>` is the page title, lowercased, non-alphanumeric → hyphens, max 40 chars.

### Step 5 — Ensure gitignore covers temp + meta files

Add the following patterns to the target repo's `.gitignore` if missing (use the Edit tool):

```
docs/confluence/*.meta.json
/tmp/_cf_*
```

`.meta.json` carries verbatim XHTML and version numbers — generally not worth tracking, and editing it by hand breaks the round-trip. If your team wants it tracked for review, override with `!docs/confluence/*.meta.json` in a per-repo `.gitignore`.

### Step 6 — Cleanup

```bash
rm -f /tmp/_cf_page.json
```

## Workflow: update

The argument is the path to a markdown file that has a sibling `.meta.json`.

### Step 1 — Validate inputs

- `<md-file>` must exist
- `<md-file>.meta.json` (or `.meta.json` sibling — derive from filename) must exist
- The agent must NOT have edited `.meta.json`. Show its size and mtime in the abort hint if validation fails.

### Step 2 — Upload any new local images

`./relative/path.png` references in the md become Confluence
attachments. Run:

```bash
python3 "$SKILL_DIR/lib/attach.py" \
  --md-file <md-file> \
  --meta-file <meta-file> \
  --host "$CONFLUENCE_HOST" \
  --user "$CONFLUENCE_USER"
```

Reads the password from the keychain via `require_secret`. On success, rewrites the md to use `[ri:imgN]` references and updates `meta.anchors`.

### Step 3 — Encode md + meta to XHTML

```bash
python3 "$SKILL_DIR/lib/storage_codec.py" encode \
  --md-file <md-file> \
  --meta-file <meta-file> \
  --out /tmp/_cf_storage.xhtml
```

### Step 4 — Push with conflict abort

```bash
python3 "$SKILL_DIR/lib/push.py" \
  --meta-file <meta-file> \
  --xhtml /tmp/_cf_storage.xhtml \
  --host "$CONFLUENCE_HOST" \
  --user "$CONFLUENCE_USER"
```

Script checks remote version vs. stored version. If they differ:

```
ERROR: page #12345678 moved from v12 to v15 since fetch.
Run /confluence-fetch 12345678 to pick up changes, then re-apply your edits.
```

On 200, the script rewrites `.meta.json` with the new version number.

### Step 5 — Cleanup

```bash
rm -f /tmp/_cf_storage.xhtml
```

## Workflow: create

The argument is a markdown file path. No `.meta.json` input — that's
what makes this create vs. update. After successful create, the skill
writes a `.meta.json` next to the md so future runs can use update.

```bash
python3 "$SKILL_DIR/lib/push.py" \
  --create \
  --md-file <md-file> \
  --space "$SPACE_KEY" \
  --parent "$PARENT_ID" \
  --title "<title from md frontmatter or first H1>" \
  --host "$CONFLUENCE_HOST" \
  --user "$CONFLUENCE_USER"
```

Macros are not supported in create (no anchors yet). Tables, headings,
lists, code blocks, links, and inline images-from-disk all work.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Editing `.meta.json` by hand | The push step refuses if its checksum doesn't match a known shape. Re-fetch. |
| Markdown-style image link with a remote URL `![](https://...)` | The codec only uploads local file paths. Remote images become regular `<a href>`. |
| Page already moved (different parent) | Update can't move pages. Skill aborts; move in Confluence first, then re-fetch. |
| Concurrent edit in browser | Conflict abort catches it. There is no auto-merge. |
| Running update against a file that was never fetched | No `.meta.json` exists; skill suggests `/confluence-create` instead. |
| Token rotation broke the keychain entry | `bash scripts/credentials/service.sh confluence verify` |
