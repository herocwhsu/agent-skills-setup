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

Concrete bash workflow lands in Task 8 of the migration plan.

## Workflow: tree-upload

Concrete bash workflow lands in Task 8 of the migration plan.

## Workflow: link-rewrite-preview

Concrete bash workflow lands in Task 8 of the migration plan.

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
