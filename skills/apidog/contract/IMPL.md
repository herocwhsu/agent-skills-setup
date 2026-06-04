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

Read OpenSpec change-id from `$STORY_DIR/intake-summary.md` frontmatter
(Phase 2 full integration). For now, derive the change-id as:
```
<jira-id-lowercase>-<slug>
```
and check `./openspec/changes/<change-id>/proposal.md` exists.

## Step 1 — Read OpenSpec proposal

Read `./openspec/changes/<change-id>/proposal.md` and
`./openspec/changes/<change-id>/design.md` (if it exists). Extract:
- Feature goal
- Affected entities
- Permission requirements
- Error conditions described

Also read `$STORY_DIR/repo-context.md` for existing API patterns.

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

Write to `$STORY_DIR/apidog/contract.md`:

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
