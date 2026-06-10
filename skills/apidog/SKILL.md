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
