---
name: utils
description: Use for cross-cutting utilities that don't belong to any single workflow gate. Subcommands install a Claude Code prompt-polishing hook (polish-input) and migrate self-hosted Confluence page trees between locations (confluence-tree). Not part of the spec-gated workflow — these are general-purpose helpers.
---

# utils

Cross-cutting utilities. Independent of the Spec-Gated workflow.

## Subcommands

| Slash command | What it does | Implementation |
|---|---|---|
| `/utils-polish-input` | Install a UserPromptSubmit hook that polishes single-line prompts via Claude Haiku as a learning side-channel. Default behavior does not change what Claude receives. | `polish-input/IMPL.md` |
| `/utils-confluence-tree-fetch <page-id>` | Walk a self-hosted Confluence page + descendants, write each as `<slug>.md` with frontmatter. Drawio/Gliffy diagrams preserved as opaque blocks; other macros flattened. | `confluence-tree/IMPL.md` |
| `/utils-confluence-tree-upload <local-dir> --parent <id> --space <KEY>` | Reconcile titles, create stub pages under `<id>` in `<KEY>`, then upload content + attachments + diagrams. | `confluence-tree/IMPL.md` |
| `/utils-confluence-link-rewrite-preview <local-dir> --parent <id>` | Dry-run: show how cross-tree links will rewrite given a destination parent. No network calls, no writes. | `confluence-tree/IMPL.md` |

## When to use which subcommand

```
Want polished prompts auto-shown after each turn → /utils-polish-input
Need to migrate a Confluence Server/DC page tree to a new parent → /utils-confluence-tree-fetch + edit + upload
Want to see how links would rewrite before actually uploading → /utils-confluence-link-rewrite-preview
```

## polish-input hook

Installed via `bash scripts/install.sh --with-hook polish-input`. The hook is
declared in `polish-input/hook.json`; the runtime command is now
`python3 ${AGENT_SKILLS_DIR}/utils/polish-input/lib/polish.py` (path updated
for the new group layout).

Credentials: either `agent-skills-setup:gemini` (Gemini API key) or
`agent-skills-setup:anthropic` (Anthropic API key). Set up with:

```bash
bash scripts/credentials/service.sh gemini add
# or
bash scripts/credentials/service.sh anthropic add
```

## confluence-tree (self-hosted Server/DC only)

Three-step flow: **fetch** the source tree, **edit** locally, then **upload**
under a destination parent. Source and destination are independent — no version
conflict check, no push-back, no round-trip. See
`confluence-tree/IMPL.md` for the full SKILL details (subcommand recipes,
frontmatter schema, diagram preservation).

## Migration note

| Old skill | New subcommand | Old slash | New slash |
|---|---|---|---|
| `polish-input` | `utils/polish-input` | (hook only, no slash) | (hook only, no slash) |
| `confluence` | `utils/confluence-tree` | `/confluence-tree-fetch` etc. | `/utils-confluence-tree-fetch` etc. |

`hook.json` was updated to point at `utils/polish-input/lib/polish.py`. Other
scripts and tests retain their existing internal layout.
