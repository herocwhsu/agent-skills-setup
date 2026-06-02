# Confluence Skill — Review Charter

Repo-specific review notes for `skills/confluence/`. Read alongside the
generic `review-pr/charter.md`.

## What this skill is, and isn't

- **Is:** a markdown round-trip tool for self-hosted Confluence pages,
  backed by a sidecar `.meta.json`.
- **Isn't:** a WYSIWYG editor, a diagram editor, a Confluence Cloud
  client, or a multi-page bulk operation tool.

## Storage-format gotchas

Confluence storage is XHTML with custom namespaces (`ac:`, `ri:`).
Things that look like HTML but aren't:

- `<ac:structured-macro>` — info panels, code blocks, expand, drawio,
  Gliffy, status pills, table-of-contents.
- `<ac:image>` with `<ri:attachment>` child — image references that
  resolve to attachment IDs at render time.
- `<ac:link>` with `<ri:page>` or `<ri:user>` — cross-page or @-mention
  links.
- `<ac:placeholder>` — UI hints that should be ignored.

Anything the codec doesn't recognize must become an opaque anchor, never
silently dropped. A dropped macro is a data-loss bug.

## Round-trip integrity rules

| Rule | Why |
|---|---|
| Decode → encode → decode produces semantically equal XHTML | Catches anchor splicing bugs |
| `meta.json` is rewritten on every successful push | Stale version causes false conflicts |
| Anchors are id-stable across re-fetch when content unchanged | Diff readability |
| Unknown elements wrap in `<!-- unknown:tag -->` not dropped | Data-loss safety |
| `.meta.json` integrity check before push | Prevents corruption from manual edits |

## Conflict handling

The conflict check is a *version-number compare*, not a content diff.
If remote version > stored version, abort. Don't try to merge —
markdown + macros is too lossy a representation to merge safely.

If you see a "the version compare passed but the push 409'd" report,
that's a race condition between the version check and the PUT, and the
correct fix is to re-check version inside the PUT response handler, not
to add retry logic.

## Attachment quirks

- `X-Atlassian-Token: nocheck` header is **mandatory** for attachment
  POST or Confluence rejects with 403.
- Attachment names must be unique per page; uploading the same filename
  twice creates two distinct attachments.
- Default upload limit on Server is 100 MB. Don't add retry logic for
  413 — the user has to split the file or change the limit.

## What to flag in review

### Critical
- Codec drops content silently (any `ac:` or `ri:` element handled by
  fall-through with no anchor created)
- Push without version check
- Credentials echoed in logs or shell traces
- `git add` of a `.meta.json` that contains raw HTML body fragments

### Important
- New macro type added to fixtures but not to the codec test matrix
- Attachment uploaded but anchor not created (md still references local path)
- `meta.json` schema changed without a migration for existing files
- Hardcoded `https://` URLs (must respect `$CONFLUENCE_HOST` only)

### Minor
- Print formatting in error messages
- Slug truncation rules
- File-naming conventions for multiple fetches in one day

## Do not over-focus on

- XHTML attribute order in encode output (semantically equivalent)
- Whitespace in the storage value (Confluence normalizes)
- Markdown line-wrap style (the user owns this)
- Whether the date prefix uses `-` or `_` (consistency with other skills wins)
