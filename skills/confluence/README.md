# confluence

Fetch, edit, create, and attach files to **self-hosted Confluence
Server/DC** pages. Round-trips macros, images, and cross-page links via
a sidecar `meta.json` (anchor-and-splice).

## Status

Scaffolding. The XHTML codec is a stub pending real-page fixtures from
the target instance. HTTP layer (push, attach) is implemented.

To complete:
1. Export 5-10 real pages as storage-format fixtures (see
   `tests/fixtures/README.md`).
2. Implement `lib/storage_codec.py decode/encode`.
3. Run `tests/test_codec_roundtrip.sh` against the fixtures.

## Install

```bash
bash scripts/install.sh
```

Installed automatically as a `local` skill once added to `registry.txt`.

## Prerequisites

- `gh` not required — uses Confluence REST directly
- `~/.agent-skills-setup/config.sh` with `CONFLUENCE_HOST`,
  `CONFLUENCE_USER`. Set up via:
  ```bash
  bash scripts/credentials/service.sh confluence add
  ```
- Python 3 with `lxml` (codec) and standard library (push, attach)

## Subcommands

| Command | Argument | Behavior |
|---|---|---|
| `/confluence-fetch` | page-id, URL, or `space:title` | Save md + meta.json under `./docs/confluence/` |
| `/confluence-update` | md file path | Re-emit XHTML, PUT, abort on version conflict |
| `/confluence-create` | md file path | New page from markdown only |

## The .meta.json contract

```json
{
  "pageId": "12345678",
  "version": 12,
  "space": "PP2",
  "ancestor": "23456789",
  "title": "My Page Title",
  "host": "confluence.example.com",
  "anchors": {
    "m1":   { "type": "macro",     "xml": "<ac:structured-macro ...>" },
    "img1": { "type": "image",     "filename": "diagram.png", "xml": "<ac:image>..." },
    "link1":{ "type": "page-link", "xml": "<ac:link><ri:page .../></ac:link>" }
  }
}
```

**Do not edit `.meta.json` by hand.** Anchors appear in the markdown as
`<!-- ac:macro id="m1" -->`, `![alt][ri:img1]`, `[title][ri:link1]`.
You can move, duplicate, or delete them. To edit what they point to,
use Confluence's web editor.

## Auth

Reads `CONFLUENCE_HOST` and `CONFLUENCE_USER` from config.
Reads password/token from the keychain.

- **Basic Auth** (default): `username:password`
- **PAT** (auto-detected): if the credential is in PAT format
  (long, no colon), the skill sends `Authorization: Bearer <token>`
  instead of Basic Auth. No credential-store change needed.

## Output Location

```
./docs/confluence/2026-06-02-my-page-title.md
./docs/confluence/2026-06-02-my-page-title.meta.json
```

`.meta.json` is gitignored by default — it contains pageId, version,
and verbatim XHTML. Add `!docs/confluence/*.meta.json` to your repo's
`.gitignore` overrides if you do want it tracked (e.g. for review).

## Why a separate skill from `fetch-page-to-markdown`

`fetch-page-to-markdown` handles general URLs (Apidog, internal wikis,
any `curl`-able page) one-way. This skill is Confluence-specific and
two-way. The other skill remains for non-Confluence URLs.

## Troubleshooting

- **`CONFLUENCE_HOST not in config.sh`** — run
  `bash scripts/credentials/service.sh confluence add`.
- **`page moved from vN to vM since fetch`** — someone else edited
  the page. Re-fetch, re-apply your edits.
- **`.meta.json checksum failed`** — you (or a tool) edited the
  meta.json. Re-fetch.
- **Macros silently dropped** — your codec hit an `ac:` element it
  doesn't recognize. Add a fixture, file an issue.
