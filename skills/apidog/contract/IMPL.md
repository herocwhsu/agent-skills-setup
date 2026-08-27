---
subcommand: contract
group: apidog
slash: /apidog-contract <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/apidog/contract.md
---

# apidog/contract — API Contract Plan

Generates the API contract from the approved OpenSpec proposal and repo
context. This document is reviewed by frontend, backend, and QA before
implementation starts.

Corresponds to workflow spec §14.7, skill 20 (apidog-contract-planner).

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

Read OpenSpec change-id from `$STORY_DIR/intake-summary.md` frontmatter:

```bash
# Read openspec_changes from intake-summary.md frontmatter
CHANGE_ID=""
if [[ -f "$STORY_DIR/intake-summary.md" ]]; then
    CHANGE_ID=$(grep -A1 "^openspec_changes:" "$STORY_DIR/intake-summary.md" \
        | grep "^-" | head -1 | sed 's/^-[[:space:]]*//')
fi

# Fallback: derive from JIRA-ID and slug if frontmatter is empty
if [[ -z "$CHANGE_ID" ]]; then
    STORY_BASENAME=$(basename "$STORY_DIR")
    CHANGE_ID=$(echo "$STORY_BASENAME" | tr '[:upper:]' '[:lower:]')
fi

# The proposal is the preferred spec source, not a hard requirement: only repos
# that use OpenSpec have one. Degrade to the story artifacts rather than exiting,
# matching testing/plan (which reads story.md when OpenSpec is absent). Exiting
# here made this gate unusable for docs/stories-only work.
SPEC_SOURCE=""
if [[ -f "./openspec/changes/$CHANGE_ID/proposal.md" ]]; then
    SPEC_SOURCE="./openspec/changes/$CHANGE_ID/proposal.md"
elif [[ -f "$STORY_DIR/audit-report.md" ]]; then
    SPEC_SOURCE="$STORY_DIR/audit-report.md"
    echo "NOTE: no OpenSpec proposal for '$CHANGE_ID'; deriving the contract from"
    echo "      $SPEC_SOURCE. Confirm endpoint shapes with a human before pushing."
elif [[ -f "$STORY_DIR/story.md" ]]; then
    SPEC_SOURCE="$STORY_DIR/story.md"
    echo "NOTE: no OpenSpec proposal and no audit report; deriving the contract from"
    echo "      $SPEC_SOURCE only. Treat every endpoint shape as unverified."
else
    echo "ERROR: no spec source found. Need one of:"
    echo "  ./openspec/changes/$CHANGE_ID/proposal.md"
    echo "  $STORY_DIR/audit-report.md"
    echo "  $STORY_DIR/story.md"
    echo "Run /intake-jira-story $1 first."
    exit 1
fi
```

`$SPEC_SOURCE` is what Step 1 reads. When it is not the proposal, say so in the
generated `contract.md` so a reviewer knows the contract was not derived from an
approved spec.

## Step 1 — Read OpenSpec proposal

Read `./openspec/changes/<change-id>/proposal.md` and
`./openspec/changes/<change-id>/design.md` (if it exists). Extract:
- Feature goal
- Affected entities
- Permission requirements
- Error conditions described

Also read `$STORY_DIR/repo-context.md` for existing API patterns.

## Step 1.5 — Decide sequential vs parallel drafting

Count the distinct API endpoints identified in Step 1 (from the proposal +
`repo-context.md`).

- **Fewer than 3 endpoints:** draft each endpoint's contract section
  yourself, one after another, in Step 2 below.
- **3 or more independent endpoints:** dispatch one sub-task per endpoint to
  draft that endpoint's contract section in isolation. Give each sub-task
  only what it needs: the endpoint's method + path, the relevant proposal
  excerpt, and the matching API pattern from `repo-context.md` — not the
  whole proposal. Use whatever native sub-agent/delegation mechanism this
  host provides. Collect each sub-task's output and assemble them in the
  same endpoint order before writing the final `contract.md`.

  Only split endpoints that are genuinely independent — if two endpoints
  share a request/response schema, or one endpoint's shape depends on
  another's (e.g. a list endpoint and its corresponding detail endpoint),
  draft those together in the same pass instead of splitting them.

## Step 2 — For each API endpoint, define

| Field | Description |
|---|---|
| Method | GET / POST / PUT / PATCH / DELETE |
| Path | e.g. `/api/v1/cameras/{cameraId}/events` |
| Summary | One-line description |
| Auth | Required auth type (Bearer, API key, etc.) |
| Permission | Which permission scopes / roles are required |
| Request schema | Body + query params + path params |
| Response schema (200) | Success response shape |
| Response schema (error) | 400/401/403/404/429/5xx |
| Pagination | Cursor / offset, max page size |
| Examples | At least one happy-path example |

## Output format

Write to `$STORY_DIR/apidog/contract.md` and then push to Apidog (Step 3):

```markdown
---
story: <JIRA-ID>
openspec_change: <change-id>
created_at: <YYYY-MM-DD>
status: draft
endpoint_count: <n>
---

# API Contract: <JIRA-ID>

## Endpoints

### 1. <Method> <Path>

**Summary:** <description>
**Auth:** Bearer token  
**Permission:** <scope or role>

#### Request

Path params:
| Param | Type | Required | Description |
|---|---|---|---|

Query params:
| Param | Type | Required | Default | Description |
|---|---|---|---|---|

Body (JSON):
```json
{
  "field": "type — description"
}
```

#### Response 200
```json
{
  "id": "string",
  ...
}
```

#### Error Responses
| Status | When | Response |
|---|---|---|
| 400 | Invalid input | `{ "error": "...", "field": "..." }` |
| 401 | Missing or invalid token | `{ "error": "unauthorized" }` |
| 403 | Insufficient permission | `{ "error": "forbidden" }` |
| 404 | Resource not found | `{ "error": "not_found" }` |
| 429 | Rate limited | `{ "error": "rate_limited" }`, `Retry-After` header |

#### Example
Request:
```
GET /api/v1/cameras/cam-123/events?from=2026-01-01&limit=20
Authorization: Bearer <token>
```
Response:
```json
{ "items": [...], "nextCursor": "..." }
```

## Review Checklist
- [ ] Frontend has reviewed and confirmed the request/response shape
- [ ] Backend has confirmed feasibility
- [ ] QA has confirmed testability
- [ ] Permission model reviewed by security/tech lead
```

## Step 3 — Push to Apidog via MCP

After the local file is written and reviewed, push the contract to Apidog.

Convert `contract.md` to an OpenAPI 3.0 spec (YAML or JSON) and call:

```
apidog_import_openapi(
  spec: <openapi-yaml-from-contract>,
  module: <module-name>,        // from APIDOG_MODULES config
  updateStrategy: "merge"       // preserve existing endpoints not in this spec
)
```

If `APIDOG_MODULES` is not set, use the default module.

On success, print:
```
Contract pushed to Apidog.
Run /apidog-diff <STORY-ID> to verify the live state matches the contract.
```

On failure, print the MCP error verbatim and stop. Do not silently swallow
push errors. The local markdown file remains as the source of truth.

## MCP prerequisite check

Before Step 3, verify the MCP server is available:

```
apidog_modules()  // should return project + module list without error
```

If this fails, tell the user to run `/infra-apidog-mcp setup` first.
