# Confluence Skill — Review Charter

Repo-specific review notes for `skills/confluence/`. Read alongside the
generic `review-pr/charter.md`.

## What this skill is, and isn't

- **Is:** a one-way migration tool for self-hosted Confluence page
  trees. Fetches a source page subtree to local markdown + sidecar
  files, lets the user edit, then uploads as a brand new tree under a
  destination parent.
- **Isn't:** a round-trip editor, a WYSIWYG, a diagram editor, a
  Confluence Cloud client, or a tool for moving pages within the same
  Confluence instance.

Source and destination are independent. There is no version conflict
check on upload because there is nothing to conflict with — the
destination pages did not exist before this run.

## Migration-specific gotchas

### Storage format: macros flatten lossy

Confluence storage is XHTML with custom namespaces (`ac:`, `ri:`).
The fetcher converts what it can to markdown:

- Headings, paragraphs, lists, tables, code blocks, inline formatting:
  converted to standard markdown.
- `<ac:link>` with `<ri:page>`: rewritten to a markdown link whose
  target is recorded in the manifest for cross-tree rewriting.
- `<ac:image>` with `<ri:attachment>`: rewritten to a markdown image
  pointing at the local attachments directory.
- **Drawio and Gliffy macros only:** preserved verbatim in
  `_root.diagrams.json`, referenced from markdown by opaque ID.
- **Every other macro** (info panels, expand, table-of-contents,
  status pills, page-properties, etc.): flattened to its rendered
  text equivalent. The original XML is kept under a `flattened` entry
  in the diagrams sidecar for reference, but the upload pass does
  not replay it. **This is lossy on purpose** — round-tripping every
  macro is out of scope for this skill.

### Manifest integrity

`manifest.json` describes the tree shape: which markdown file maps to
which source page ID, who its parent is, and where its attachments
live. **The on-disk tree is the source of truth, not the manifest.**
Between fetch and upload the user may rename, move, or delete files.
The upload entrypoint must re-build the manifest from the on-disk
tree before pass 1 — never trust the file the fetcher wrote.

### Two-pass upload

Upload runs in two strict passes:

1. **Stub pass:** create empty pages under the destination parent in
   tree order (root first, then breadth-first). Record the new page
   ID for each `source_page_id` in an in-memory rewrite map.
2. **Content pass:** for each page, rewrite cross-tree links using
   the map from pass 1, upload attachments, replay diagrams, then
   PUT the storage-format body to the stub.

If any stub creation in pass 1 fails, the upload aborts and the
content pass never runs. Stubs left behind in Confluence are empty
and safe to delete by hand. Don't add retry/skip logic — partial
trees are worse than no tree.

### Attachment naming

Attachment names must be unique per destination page. The fetcher
stores attachments under a per-page directory keyed by source
filename; the upload pass uses the **same source filename** as the
destination filename so that markdown image references stay stable
through the edit phase. Renaming an attachment file on disk breaks
its markdown reference — use markdown alt text for human-readable
labels instead.

### Cross-tree links

Cross-tree links are rewritten **only** when the link target's
`source_page_id` is present in the local tree's manifest. Links to
pages outside the fetched subtree stay as their original
`https://<source-host>/...` URL. The
`/confluence-link-rewrite-preview` subcommand is the way to confirm
which links rewrite vs. stay before running upload — use it.

## What to flag in review

### Critical

- Upload pass 2 starts before pass 1 has confirmed all stub IDs
- Manifest used directly from disk without rebuilding from the tree
- Drawio or Gliffy macro silently flattened (must always preserve in
  diagrams sidecar)
- Cross-tree link rewritten to a destination ID for a `source_page_id`
  that wasn't in the rebuilt manifest (false-positive rewrite)
- Credentials echoed in logs or shell traces
- Partial-stub failure that proceeds to content upload anyway

### Important

- Attachment >100 MB silently uploaded (must refuse before POST)
- Macro converter adds support for a new macro but doesn't update
  the flattened-list documentation
- `source_page_id` overwritten on re-fetch (must be stable per page)
- Hardcoded `https://` URLs (must respect `$CONFLUENCE_HOST` only)
- Upload uses a different `--space` than the destination parent
  actually lives in (must validate before pass 1)
- `_root.diagrams.json` schema changed without migration for files
  fetched under the previous schema

### Minor

- Slug truncation rules
- Print formatting in error messages
- Whether the directory date prefix uses `-` or `_` (consistency
  with other skills wins)
- Markdown line-wrap style in the converter output (the user owns
  this after fetch)

## Do not over-focus on

- XHTML attribute order in encode output (Confluence normalizes)
- Whitespace in the storage value
- Round-trip fidelity for non-diagram macros (out of scope by design)
- Whether a flattened macro could in principle be recreated on the
  destination — if it's not drawio/Gliffy, the answer is "manually,
  later, in the Confluence editor"
