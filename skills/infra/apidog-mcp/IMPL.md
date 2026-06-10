---
subcommand: apidog-mcp
group: infra
slash: /infra-apidog-mcp <subcommand>
---

# infra/apidog-mcp — Apidog MCP Server Setup

Installs and configures `@lstpsche/apidog-mcp` for use with Claude Code,
Kiro, and Gemini CLI. The MCP server proxies all Apidog CRUD operations
through the Model Context Protocol using your access token.

## Subcommands

| Subcommand | What it does |
|---|---|
| `setup` | Install the MCP server and wire credentials into agent settings |
| `status` | Verify the MCP server is reachable and credentials are valid |
| `remove` | Remove the MCP server config from agent settings |

## Prerequisites

- Node.js ≥ 18
- Apidog access token stored in keychain:
  ```bash
  bash scripts/setup-credentials.sh apidog add
  ```
- `APIDOG_PROJECT_ID` set in `~/.agent-skills-setup/config.sh`

## Setup workflow

### Step 1 — Verify credentials

The keychain entry stores email and token concatenated. Extract just the token:

```bash
RAW=$(security find-generic-password -s "agent-skills-setup:apidog" -w 2>/dev/null) || {
  echo "ERROR: Apidog token not found. Run: bash scripts/setup-credentials.sh apidog add"
  exit 1
}
APIDOG_ACCESS_TOKEN=$(echo "$RAW" | grep -o 'adgp_[^[:space:]]*') || {
  echo "ERROR: Could not extract token from keychain entry. Expected format: <email>adgp_<token>"
  exit 1
}
[[ -n "${APIDOG_PROJECT_ID:-}" ]] || {
  echo "ERROR: APIDOG_PROJECT_ID not set in ~/.agent-skills-setup/config.sh"
  exit 1
}
```

### Step 2 — Install the package globally

```bash
npm install -g @lstpsche/apidog-mcp
```

Verify:
```bash
npx @lstpsche/apidog-mcp --version
```

### Step 3 — Wire into agent settings

Add the MCP server to each agent's settings using `update-config` skill or
by editing directly. The token is injected from the environment — never
hardcoded in settings files.

For Claude Code (`~/.claude/settings.json`):
```json
{
  "mcpServers": {
    "apidog": {
      "command": "npx",
      "args": ["-y", "@lstpsche/apidog-mcp"],
      "env": {
        "APIDOG_ACCESS_TOKEN": "${APIDOG_ACCESS_TOKEN}",
        "APIDOG_PROJECT_ID": "${APIDOG_PROJECT_ID}"
      }
    }
  }
}
```

For Kiro (`~/.kiro/settings/mcp.json`), same structure under `mcpServers`.

### Step 4 — Verify connection

After wiring, ask the agent to call `apidog_modules` with no arguments.
Expected output: list of configured projects and modules. If it returns an
auth error, re-check the token value.

## Status check

```bash
RAW=$(security find-generic-password -s "agent-skills-setup:apidog" -w 2>/dev/null)
APIDOG_ACCESS_TOKEN=$(echo "$RAW" | grep -o 'adgp_[^[:space:]]*')
curl -s -X POST \
  -H "Authorization: Bearer $APIDOG_ACCESS_TOKEN" \
  -H "X-Apidog-Api-Version: 2024-03-28" \
  -H "Content-Type: application/json" \
  -d '{"scope":{"type":"ALL"},"options":{"includeApidogExtensionProperties":false,"addFoldersToTags":false},"oasVersion":"3.0","exportFormat":"JSON","moduleId":0}' \
  "https://api.apidog.com/v1/projects/${APIDOG_PROJECT_ID}/export-openapi?locale=en-US" | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK — paths:', len(d.get('paths',{})))"
```

## Remove

To unregister the MCP server, remove the `apidog` key from `mcpServers` in
each agent's settings file. The globally installed npm package can stay.

## Environment variables used

| Variable | Source | Description |
|---|---|---|
| `APIDOG_ACCESS_TOKEN` | Keychain — extract with `grep -o 'adgp_[^[:space:]]*'` | Personal access token (`adgp_...`) from Apidog Settings |
| `APIDOG_PROJECT_ID` | `~/.agent-skills-setup/config.sh` | Default project ID |
| `APIDOG_MODULES` | Optional, `config.sh` | JSON map of module names to IDs |

## API notes

All Apidog API calls require:
- `Authorization: Bearer <APIDOG_ACCESS_TOKEN>`
- `X-Apidog-Api-Version: 2024-03-28`
- `Content-Type: application/json`

Base URL: `https://api.apidog.com/v1/projects/{projectId}/`
