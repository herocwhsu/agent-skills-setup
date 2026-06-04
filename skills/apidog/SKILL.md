---
name: apidog
description: Use after the OpenSpec proposal is approved to plan and document the API contract, mock responses, and test cases in Apidog. Apidog is an implementation gate for API features — contract must be approved before backend coding starts. Three subcommands: contract, mocks, testcases.
---

# apidog

Plans the API contract, mock data, and test cases that gate implementation.

The recommended sequence (workflow spec §4.5):
```
OpenSpec approved
↓
/apidog-contract <STORY-ID>    ← plan the API contract
↓
Frontend / backend / QA review
↓
/apidog-mocks <STORY-ID>       ← generate mock responses
/apidog-testcases <STORY-ID>   ← generate API test cases
↓
Implementation starts
```

Never update Apidog after implementation as documentation only. It is a gate.

## Subcommands

| Slash command | What it does | Output |
|---|---|---|
| `/apidog-contract <STORY-ID>` | Generate API contract plan from the OpenSpec proposal and repo context. | `./docs/stories/<ID>-<slug>/apidog/contract.md` |
| `/apidog-mocks <STORY-ID>` | Generate mock response examples (success, empty, error, auth). | `./docs/stories/<ID>-<slug>/apidog/mocks.md` |
| `/apidog-testcases <STORY-ID>` | Generate API test cases (positive, negative, boundary, permission, pagination). | `./docs/stories/<ID>-<slug>/apidog/testcases.md` |

## Prerequisites

- OpenSpec proposal exists at `./openspec/changes/<change-id>/proposal.md`
  (created by `/opsx:propose`)
- `./docs/stories/<STORY-ID>-<slug>/` exists
- Apidog credentials (optional — used only if writing directly to Apidog via API):
  ```bash
  bash scripts/credentials/service.sh apidog add
  ```

## Credentials

`agent-skills-setup:apidog` keychain entry plus `APIDOG_PROJECT_ID` and
`APIDOG_TOKEN` in `~/.agent-skills-setup/config.sh`. Set up with:

```bash
bash scripts/credentials/service.sh apidog add
```

These are optional for Phase 2. The skills write the contract/mocks/testcases
as markdown files in the story folder. Actual Apidog import is manual for now.
