# confluence Skill: Implementation Plan

**Date:** 2026-06-02
**Status:** Pending approval (test fixtures from real pages still needed before Task 1)

## Goal

Build a `confluence` skill that fetches, edits, creates, and attaches files to **self-hosted Confluence Server/DC** pages, preserving macros and images via an anchor-and-splice round-trip.

## Decisions captured

| Question | Answer |
|---|---|
| Target Confluence | Self-hosted Server/DC |
| Auth | Basic Auth default; PAT auto-detected when password slot starts with `Bearer `-able token (no credential-store change) |
| Scope | Create + round-trip edit + attachment upload |
| Transport | MCP-first (sooperset/mcp-atlassian), REST fallback |
| Diagrams (drawio/Gliffy) | Level A: preserved opaque, no in-skill editing |
| Version conflict | Abort on mismatch with refetch hint |
| Existing `fetch-page-to-markdown` | Keep; narrows to general-purpose URLs |
| `fetch-jira-story` integration | Switch confluence link follow-through to new skill (Task 10) |

## Approach: anchor-and-splice

Markdown can't represent Confluence macros, `<ac:image>`, or `<ac:link>`. So:

```
fetch:  XHTML  →  md  + sidecar meta.json
                  └── markers like  <!-- ac:macro id="m1" -->
                                    ![alt][ri:img1]
edit:   user edits md (markers can be moved or deleted, not edited)
push:   md + meta.json  →  XHTML (re-splice macros at marker positions)
```

`.meta.json` is the source of truth for: `pageId`, `version`, `space`, `ancestor`, plus an `anchors` map keyed by `m1`/`img1`/etc. Each anchor entry holds the verbatim XML fragment.

## File structure

```
skills/confluence/
├── SKILL.md
├── README.md
├── charter.md                  (review gotchas: storage format, version conflicts, attachment quirks)
├── lib/
│   ├── storage_codec.py        (XHTML ↔ md+meta round-trip)
│   ├── push.py                 (PUT with version bump, conflict abort)
│   ├── attach.py               (multipart POST attachment)
│   └── mcp_adapter.py          (MCP-first dispatch, REST fallback)
└── tests/
    ├── fixtures/               (real pages, exported from your instance)
    │   ├── simple.xml
    │   ├── info-macro.xml
    │   ├── code-macro.xml
    │   ├── image-attachment.xml
    │   ├── drawio.xml
    │   └── expand.xml
    ├── test_codec_roundtrip.sh
    ├── test_push_conflict.sh
    └── test_attach.sh
```

## Tasks (ordered, each independently testable)

### Task 1 — `storage_codec.py` fetch direction (XHTML → md + meta.json)
- Parse with lxml in namespaced mode (`ac:`, `ri:`)
- Translate: headings/lists/tables/links/code/text → markdown
- `<ac:structured-macro>` → `<!-- ac:macro id="m{N}" -->` token; full XML stored in `meta.anchors.m{N}`
- `<ac:image>` (with `ri:attachment`) → `![{alt}][ri:img{N}]`; attachment metadata in `meta.anchors.img{N}`
- `<ac:link><ri:page/></ac:link>` → `[{title}][ri:link{N}]`
- Anything else unknown → opaque token (better than dropping)
- **Tests:** parse each fixture, assert round-trip Tasks 1+2 produces semantically equivalent XHTML

### Task 2 — `storage_codec.py` push direction (md + meta.json → XHTML)
- Markdown parser: any standard one that supports tables and link-references
- On encountering a marker (`<!-- ac:macro id=... -->`, `![...][ri:...]`, `[...][ri:link...]`), splice the verbatim XML from `meta.anchors`
- Markers whose IDs aren't in `meta.anchors` → emit a clearly-marked XHTML comment, never silently drop
- **Tests:** XHTML → md → XHTML on every fixture; semantic equivalence (whitespace ignored, attribute order ignored)

### Task 3 — `push.py` REST update with conflict abort
- Read `meta.pageId`, `meta.version`
- `GET /rest/api/content/{id}?expand=version`
- If `live.version.number != meta.version` → abort:
  ```
  ERROR: page #{id} moved from v{stored} to v{live} since fetch.
  Run /confluence-fetch {id} to pick up changes, then re-apply your edits.
  ```
- Else `PUT /rest/api/content/{id}` with `body.storage.value = recomposed`, `version.number = stored + 1`
- On 200: rewrite `meta.json` with new version
- **Tests:** mock REST endpoint (Python `http.server` fixture); assert PUT body + version + abort path

### Task 4 — `attach.py` upload local images
- Scan md for `![...](./relative-path)` (i.e. file paths, not anchors)
- For each: `POST /rest/api/content/{id}/child/attachment` (multipart, `X-Atlassian-Token: nocheck`)
- On success: rewrite md to `![alt][ri:img{N}]` and add `meta.anchors.img{N}`
- Then run Task 3 push
- **Tests:** mock multipart endpoint; assert correct boundary, filename, post-upload md/meta state

### Task 5 — SKILL.md fetch workflow
- Env check: `CONFLUENCE_HOST`, `CONFLUENCE_USER` from `~/.agent-skills-setup/config.sh`
- MCP detection: try `confluence_get_page` tool first; on missing tool, fall through
- REST fallback: GET `?spaceKey=...&title=...&expand=body.storage,version,space,ancestors`
- Run codec, write `./docs/confluence/{YYYY-MM-DD}-{slug}.md` + `.meta.json`

### Task 6 — SKILL.md update workflow
- Read sibling `.meta.json`
- Run `attach.py` first (upload any new local images)
- Run `push.py` (PUT with version bump or abort)
- On success, update `.meta.json` with returned version

### Task 7 — SKILL.md create workflow
- `--space PP2 --parent {pageId}` arguments
- No `.meta.json` input required (that's what makes it create vs. update)
- POST `/rest/api/content` with `type=page`, `space.key`, `ancestors`, `body.storage`
- After create, save `.meta.json` for future updates

### Task 8 — `mcp_adapter.py`
- Detection: skill probes for `confluence_get_page` / `confluence_update_page` / `confluence_attach_file` MCP tools at runtime via the agent's tool registry
- When MCP available, all three workflows route through it (cheaper, handles auth)
- When not, the Python helpers in `lib/` run via Bash
- **Tests:** deferred (need MCP harness; not blocking)

### Task 9 — README and charter
- README: install, the meta.json contract, common workflows, Basic Auth vs PAT auto-detect
- charter.md: review gotchas — storage-format edge cases, attachment race conditions, what `meta.json` integrity means, "never edit `.meta.json` by hand"

### Task 10 — `fetch-jira-story` integration
- Detect Confluence link → if `confluence` skill is installed, route there (fetches with macros preserved); else fall back to current `fetch-page-to-markdown`
- Output filename matches existing `confluence-{pageId}.md` for backwards-compat
- **Tests:** run jira-story end-to-end against a fixture issue with a confluence link

### Task 11 — registry + install
- Add `local  confluence` to `registry.txt`
- Verify install on macOS + Linux + Windows install scripts (no special handling expected)
- Optionally: add sooperset/mcp-atlassian as a `pip` registry entry so MCP works out of the box

## Risks & open questions

1. **Storage-format diversity.** Old Confluence versions have CDATA quirks, namespace inconsistencies, and macro variants the codec may not handle. **Mitigation:** collect real fixtures from your instance before Task 1, not synthetic ones.

2. **Markdown round-trip fidelity** for nested lists, merged-cell tables, code blocks containing markdown. The codec aims for *semantic* round-trip — bytes won't always match. Tests assert XHTML equivalence after a normalization pass, not byte equality.

3. **Attachment 100MB cap.** Default Confluence limit. Skill must fail fast with a clear message and not retry partial uploads.

4. **Concurrent edits while user is editing locally.** Conflict abort catches this on push, but the user has lost work-in-progress. Documenting this in the charter; not adding auto-merge.

5. **MCP install.** `sooperset/mcp-atlassian` is a separate concern. Default plan: skill works without it (REST). Optional registry entry adds it if requested.

## What I need from you before Task 1 starts

To make the codec hold up against real pages, please export 5-10 storage-format snapshots from your instance:

```bash
curl -u $USER:$PASS \
  "https://$CONFLUENCE_HOST/rest/api/content/{PAGE_ID}?expand=body.storage" \
  | jq -r '.body.storage.value' > fixture-{N}.xml
```

Mix of:
- One simple page (text + headings + lists)
- One with a table (preferably with merged cells if you have one)
- One with an info/warning/note macro
- One with a code macro (language attribute set)
- One with an image attachment
- One with drawio
- One with expand/details
- One with cross-page `<ac:link>`

Drop them anywhere — I'll wire them into `tests/fixtures/`. Without these, the codec is guessing.

## Out of scope (for v1)

- Atlassian Cloud (different API base, different storage format ADF) — separate skill if needed later
- Drawio diagram XML editing (Level B) — opaque preservation only
- Page move / delete / permissions
- Comments and inline annotations
- Watching for remote changes (no polling, no webhook)
- Bulk operations (1 page at a time)
