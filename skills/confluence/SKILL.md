---
name: confluence
description: Use when the user wants to migrate a Confluence page tree to a new location. Fetches a source page and all descendants as markdown, lets the user edit locally, then uploads the tree under a different parent page. Drawio/Gliffy diagrams preserved as opaque blocks; other macros flattened. Self-hosted Server/DC only.
---

# confluence

Migrate a **self-hosted Confluence Server/DC** page tree to a new
location. Fetches a source page plus all descendants to local markdown,
lets the user edit and reorganize, then uploads the result as a brand
new page tree under a different parent.

## Overview

Three steps, run in order: **fetch** the source tree to local markdown,
**edit** the files in your editor of choice (rename, reorder, rewrite,
delete), then **upload** the edited tree under a destination parent.
Source and destination are independent — there is no version conflict
check, no push-back, no round-trip. Drawio and Gliffy diagrams are
preserved verbatim as opaque blocks so they continue to render after
upload; other Confluence macros are flattened to their best markdown
equivalent on fetch.

## Subcommands

| Command | What it does |
|---|---|
| `/confluence-tree-fetch <page-id>` | Walk the source page and descendants; write each as `<slug>.md` with frontmatter, plus `_root.attachments/`, `_root.diagrams.json`, and `manifest.json` describing the tree shape |
| `/confluence-tree-upload <local-dir> --parent <id> --space <KEY>` | Re-build the manifest from the on-disk tree, create stub pages under `<id>` in `<KEY>` (pass 1), then upload content + attachments + diagrams (pass 2) |
| `/confluence-link-rewrite-preview <local-dir> --parent <id>` | Dry-run: show how cross-tree links will rewrite given the destination parent. No network calls, no writes. |

## Frontmatter contract

Each fetched markdown file carries this YAML frontmatter. **Never edit
`source_page_id` by hand** — the upload pass uses it to match
cross-tree links and to detect manifest drift. Other fields are
informational; you can change `source_title` if you want to rename the
page on upload (the upload pass uses the on-disk filename slug for the
URL, but `source_title` for the page title).

```yaml
---
source_page_id: "12345678"
source_title: "VADP work / setup notes"
source_url: "https://confluence.example.com/display/RD/VADP-work"
source_version: 42
fetched_at: "2026-06-03"
attachments_dir: "./_root.attachments"
diagrams_file: "./_root.diagrams.json"
---
```

## Diagram sidecar contract

Drawio and Gliffy diagrams cannot be losslessly converted to markdown,
so the fetcher does not try. Each diagram is preserved as an entry in
`_root.diagrams.json` keyed by an opaque ID, and referenced from the
markdown as a single line:

```
<!-- diagram id="d1" -->
```

The sidecar stores the diagram's macro XML, attachment filename, and
source page ID. The upload pass replays diagrams as their original
macros pointing at the re-uploaded attachments — the diagrams render
in the destination tree exactly as they did in the source.

To **edit** a diagram, finish the migration first, then open the
destination page in Confluence's web editor and edit the diagram
there. Editing the JSON sidecar by hand is not supported.

## Auth

Reads `CONFLUENCE_HOST` and `CONFLUENCE_USER` from
`~/.agent-skills-setup/config.sh`; reads the password/token from the
keychain via `require_secret`.

- **Default:** Basic Auth (`username:password`).
- **PAT auto-detect:** if the credential value matches PAT format
  (`[A-Za-z0-9_=-]{30,}` and contains no `:`), the skill switches to
  `Authorization: Bearer <token>` automatically. No credential-store
  change needed.

## Workflow: tree-fetch

> **Note:** The bash recipes below assume Claude Code (`$HOME/.claude/skills/confluence`). On Gemini CLI, Kiro, Copilot, or Codex, change `SKILL_DIR` to the matching path (e.g., `$HOME/.gemini/skills/confluence`).

Argument: the source page ID. Output lands at `./docs/confluence/<YYYY-MM-DD>-<page-id>/` relative to the user's CWD.

```bash
SKILL_DIR="$HOME/.claude/skills/confluence"

source ~/.agent-skills-setup/lib.sh
load_config || exit 1
[[ -z "${CONFLUENCE_HOST:-}" ]] && { echo "ERROR: CONFLUENCE_HOST not in config.sh — run: bash scripts/credentials/service.sh confluence add" >&2; exit 1; }

PAGE_ID="$1"   # the slash-command argument
OUT_DIR="./docs/confluence/$(date +%Y-%m-%d)-${PAGE_ID}"

SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
_PASS=$(require_secret "$SLUG" "$CONFLUENCE_USER") || exit 1

CONFLUENCE_PASS="$_PASS" python3 "$SKILL_DIR/lib/tree_fetch.py" \
  --host "$CONFLUENCE_HOST" \
  --user "$CONFLUENCE_USER" \
  --root-id "$PAGE_ID" \
  --out-dir "$OUT_DIR"

unset _PASS
echo "Done. Tree saved at: $OUT_DIR"
echo "Edit the markdown files, then run /confluence-tree-upload to push to a new parent."
```

## Workflow: tree-upload

Arguments: the local tree directory (produced by tree-fetch and optionally edited), the destination parent page ID, and the destination space key. The upload runs in two passes — stub creation, then content + attachments + diagrams — and aborts before pass 2 if any stub fails.

```bash
SKILL_DIR="$HOME/.claude/skills/confluence"

source ~/.agent-skills-setup/lib.sh
load_config || exit 1
[[ -z "${CONFLUENCE_HOST:-}" ]] && { echo "ERROR: CONFLUENCE_HOST not in config.sh" >&2; exit 1; }

LOCAL_DIR="$1"
NEW_PARENT="$2"
SPACE_KEY="$3"

# Validate inputs
[[ -d "$LOCAL_DIR" ]] || { echo "ERROR: $LOCAL_DIR is not a directory" >&2; exit 1; }
[[ -f "$LOCAL_DIR/manifest.json" ]] || { echo "ERROR: $LOCAL_DIR/manifest.json missing — was this directory produced by /confluence-tree-fetch?" >&2; exit 1; }
[[ -n "$NEW_PARENT" ]] || { echo "ERROR: --parent <id> required" >&2; exit 1; }
[[ -n "$SPACE_KEY" ]] || { echo "ERROR: --space <KEY> required" >&2; exit 1; }

SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
_PASS=$(require_secret "$SLUG" "$CONFLUENCE_USER") || exit 1

CONFLUENCE_PASS="$_PASS" python3 "$SKILL_DIR/lib/tree_upload.py" \
  --tree "$LOCAL_DIR" \
  --new-parent "$NEW_PARENT" \
  --space "$SPACE_KEY" \
  --host "$CONFLUENCE_HOST" \
  --user "$CONFLUENCE_USER"

unset _PASS
```

## Workflow: link-rewrite-preview

Dry-run via `tree_upload.py --dry-run`. No network operations, no credentials needed — confirms which `wiki://page/<title>` links would resolve against the local manifest versus pass through unchanged.

```bash
SKILL_DIR="$HOME/.claude/skills/confluence"

LOCAL_DIR="$1"
NEW_PARENT="$2"

[[ -d "$LOCAL_DIR" ]] || { echo "ERROR: $LOCAL_DIR is not a directory" >&2; exit 1; }
[[ -n "$NEW_PARENT" ]] || { echo "ERROR: --parent <id> required" >&2; exit 1; }

# Dry-run mode skips network — no credentials needed.
# --space and --host are required by argparse but unused in dry-run; pass placeholders.
python3 "$SKILL_DIR/lib/tree_upload.py" \
  --tree "$LOCAL_DIR" \
  --new-parent "$NEW_PARENT" \
  --space PLACEHOLDER \
  --host "${CONFLUENCE_HOST:-placeholder.local}" \
  --user "${CONFLUENCE_USER:-preview}" \
  --dry-run
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Editing `source_page_id` in frontmatter by hand | The upload pass uses it as the join key for cross-tree links. Re-fetch the page if you need a clean ID. |
| Running `/confluence-tree-upload` before the manifest is rebuilt | The upload entrypoint re-builds `manifest.json` from the on-disk tree on every run. If you bypass that step (e.g. call internal scripts directly), stub creation will misalign with content. Always go through the subcommand. |
| `CONFLUENCE_HOST` missing from `~/.agent-skills-setup/config.sh` | Run `bash scripts/credentials/service.sh confluence add` to populate config + keychain in one go. |
| Mixing PAT and Basic Auth credentials in the keychain | The auto-detect rule is value-shape based: long, no colon → Bearer. If your password happens to look PAT-shaped, the skill will guess wrong. Force Basic by adding any non-alphanumeric char to the password, or rotate to a real PAT. |
| Uploading to a parent in the wrong space | The upload pass uses `--space <KEY>` for ALL stub pages; if `<id>` lives in a different space, Confluence rejects with 400. Verify the parent's space before running. |
| Cross-tree link to a page outside the local tree | Links to pages whose `source_page_id` is not present in the manifest stay as the original URL (pointing at the source instance). Use `/confluence-link-rewrite-preview` to see which links rewrite vs. stay. |
| Macro that the converter doesn't recognize | Unknown macros render as `<!-- unknown-macro: <name> -->` placeholders in the markdown with the original XML in `_root.diagrams.json` under a `flattened` key. The page uploads, but the macro becomes a plain comment — flag in review and add converter support if the macro is common. |
| Attachment >100 MB | Server's default upload limit is 100 MB. The fetch step warns and skips; the upload step refuses to proceed if the local file is over the limit. Split the attachment or change the Confluence limit before retrying. |
