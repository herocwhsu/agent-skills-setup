---
name: apidog
description: Use after the OpenSpec proposal is approved to plan and document the API contract, mock responses, and test cases in Apidog. Subcommands generate local markdown then push directly to Apidog via MCP. Four subcommands: contract, mocks, testcases, diff.
---

# apidog

Plans the API contract, mock data, and test cases that gate implementation.
Each subcommand writes a local markdown file first (for human review), then
pushes to Apidog via the `@lstpsche/apidog-mcp` MCP server.

The recommended sequence (workflow spec §4.5):
```
OpenSpec approved
↓
/apidog-contract <STORY-ID>    ← generate contract + push to Apidog
↓
Frontend / backend / QA review
↓
/apidog-diff <STORY-ID>        ← verify Apidog matches the contract
↓
/apidog-mocks <STORY-ID>       ← generate mocks + push cases to Apidog
/apidog-testcases <STORY-ID>   ← generate test cases + push to Apidog
↓
Implementation starts
```

Never update Apidog after implementation as documentation only. It is a gate.

## Subcommands

| Slash command | What it does | Output |
|---|---|---|
| `/apidog-contract <STORY-ID>` | Generate API contract from the OpenSpec proposal, write locally, push to Apidog via MCP. | `./docs/stories/<ID>-<slug>/apidog/contract.md` + Apidog |
| `/apidog-mocks <STORY-ID>` | Generate mock response examples, write locally, push cases to Apidog via MCP. | `./docs/stories/<ID>-<slug>/apidog/mocks.md` + Apidog |
| `/apidog-testcases <STORY-ID>` | Generate API test cases, write locally, push to Apidog via MCP. | `./docs/stories/<ID>-<slug>/apidog/testcases.md` + Apidog |
| `/apidog-diff <STORY-ID>` | Compare local contract against live Apidog state. Report missing, extra, and drifted endpoints. | stdout only |

## Prerequisites

- OpenSpec proposal exists at `./openspec/changes/<change-id>/proposal.md`
- `./docs/stories/<STORY-ID>-<slug>/` exists
- Apidog MCP server configured. Set up once per machine:
  ```bash
  bash scripts/setup-credentials.sh apidog add   # store token in keychain
  /infra-apidog-mcp setup                        # install + wire MCP server
  ```

## Credentials

`APIDOG_ACCESS_TOKEN` stored in macOS Keychain via `setup-credentials.sh`.
`APIDOG_PROJECT_ID` and optional `APIDOG_MODULES` set in
`~/.agent-skills-setup/config.sh`.

The MCP server reads credentials from the environment — never from committed
files. See `infra/apidog-mcp/IMPL.md` for setup details.

## Apidog Access Mode Decision Tree

Apidog has four read/write surfaces and they don't compose. Pick by what you're doing, not by what's configured:

| Goal | Path | Why |
|---|---|---|
| Read default branch (one endpoint) | MCP `apidog_get` | Branch-aware, fast |
| Read default branch (full spec) | MCP `apidog_export` | Single call, includes schemas |
| Read non-default branch (e.g. Sprint 90) | `scripts/apidog-share-fetch.py --share-uuid <uuid>` | MCP has no branch flag; Apidog REST `/v1/shared-docs/<uuid>/export-openapi` redirects to docs (verified 2026-06-18) |
| Write (create/update/wipe) | MCP `apidog_import_openapi` / `apidog_update` | Default branch only — branch writes go through the UI |

The share-fetch script reads the public share link's Remix `.data` loader and decodes the turbo-stream payload (positional `_N` slot refs). Output is normalized JSON with `id`, `method`, `path`, `name`, `status`, `description`, `request`, `responses[].type_enums`. See `scripts/apidog-share-fetch.py --help`.

Don't try to read non-default branches via the MCP or REST. The MCP package source has zero `branch` strings (`grep -i branch dist/index.js`); the REST path silently redirects. Both verified 2026-06-18 during VOR-31255.
