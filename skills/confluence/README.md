# confluence

Migrate a **self-hosted Confluence Server/DC** page tree to a new
location. Source and destination are independent — fetch is one-way
out, upload is one-way in.

## Status

Migration tool. Fetches a Confluence page tree to local markdown, lets
the user edit, uploads as a new page tree under a different parent.
Self-hosted Server/DC only.

## Install

```bash
bash scripts/install.sh
```

Installed automatically as a `local` skill once added to `registry.txt`.

## Prerequisites

- `~/.agent-skills-setup/config.sh` with `CONFLUENCE_HOST` and
  `CONFLUENCE_USER`. Set up via:
  ```bash
  bash scripts/credentials/service.sh confluence add
  ```
- Python 3 with `lxml` (storage-format parsing) and standard library
  (HTTP, manifest building)
- `jq` for manifest and diagram-sidecar inspection during debugging

## Subcommands

| Command | Argument | Behavior |
|---|---|---|
| `/confluence-tree-fetch` | source page ID | Walk source page + descendants; write markdown tree, attachments, diagram sidecar, and manifest under `./docs/confluence/<slug>/` |
| `/confluence-tree-upload` | local dir, `--parent <id>`, `--space <KEY>` | Re-build manifest, create stub pages under `<id>`, then upload content + attachments + diagrams |
| `/confluence-link-rewrite-preview` | local dir, `--parent <id>` | Dry-run; print which cross-tree links will rewrite to destination IDs and which stay as source URLs |

## Output Location

```
./docs/confluence/<root-slug>/
  manifest.json
  _root.attachments/
    diagram.png
    flowchart.svg
  _root.diagrams.json
  index.md                 # the root page
  setup-notes.md
  child-page/
    grandchild-page.md
    grandchild-page.attachments/
      ...
```

The directory mirrors the source page tree. Each markdown file owns the
attachments directory at its sibling path; diagrams live in a single
top-level `_root.diagrams.json` keyed by opaque ID.

## Auth

Reads `CONFLUENCE_HOST` and `CONFLUENCE_USER` from config. Reads
password/token from the keychain.

- **Basic Auth** (default): `username:password`
- **PAT** (auto-detected): if the credential is in PAT format (long,
  no colon), the skill sends `Authorization: Bearer <token>` instead
  of Basic Auth. No credential-store change needed.

## Why this is separate from `fetch-page-to-markdown` and `fetch-jira-story`

- **`fetch-page-to-markdown`** is a general one-shot URL-to-markdown
  fetcher. It handles any `curl`-able page (Apidog, internal wikis,
  one Confluence page at a time) and does not walk descendants, build
  manifests, or rewrite cross-page links. Use it when you need a
  reference snapshot of a single URL.
- **`fetch-jira-story`** chains from a Jira story and follows embedded
  Confluence and Apidog links into reference files. It is a one-shot
  fetch keyed by Jira ID, not a tree walk.
- **`confluence`** (this skill) is a recursive page-tree migration
  tool. It walks a page subtree, preserves drawio/Gliffy diagrams,
  rewrites cross-tree links to point at destination IDs, and uploads
  the edited tree to a new parent. Use it when you are *moving* a
  body of pages, not just reading one.

## Troubleshooting

- **`CONFLUENCE_HOST not in config.sh`** — run
  `bash scripts/credentials/service.sh confluence add`.
- **Stub creation aborted partway through upload** — the upload is
  two-pass; if pass 1 (stubs) fails, no content is uploaded. Delete
  the partial stubs in Confluence (they are empty) and re-run.
- **Cross-tree link did not rewrite** — its target's
  `source_page_id` is not present in `manifest.json`. Either fetch a
  larger subtree that includes the target, or accept that the link
  stays pointing at the source instance.
- **Diagram failed to upload** — diagrams replay as their original
  macro XML; if the destination space's macro permissions differ from
  the source's, the macro may be rejected. Check the destination
  space's allowlist.
- **Macro flattened to placeholder comment** — the converter does not
  recognize the macro type. The original XML is preserved in
  `_root.diagrams.json` under a `flattened` entry; copy it manually
  into the destination page if you need it back.
