---
subcommand: mocks
group: apidog
slash: /apidog-mocks <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/apidog/mocks.md
---

# apidog/mocks — Mock Response Generator

Generates mock API responses for all scenarios. Used for frontend development
and contract testing before the backend is implemented.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
STORY_DIR=$(resolve_story_dir "$1") || exit 1
[[ -f "$STORY_DIR/apidog/contract.md" ]] || { echo "ERROR: run /apidog-contract first" >&2; exit 1; }
```

## For each endpoint, generate these mock scenarios

| Scenario | Description |
|---|---|
| Success | Valid request, full response |
| Empty result | Valid request, zero items (for list endpoints) |
| Not found | Resource doesn't exist |
| Permission denied | Valid token, insufficient permission (403) |
| Invalid request | Missing required field or bad format (400) |
| Unauthorized | Missing or expired token (401) |
| Rate limited | 429 with Retry-After header |
| Server error | 500 for testing error UI |

## Output format

Write to `$STORY_DIR/apidog/mocks.md`:

```markdown
---
story: <JIRA-ID>
created_at: <YYYY-MM-DD>
---

# API Mock Responses: <JIRA-ID>

## <Method> <Path>

### Success (200)
```json
{ ... realistic example data ... }
```

### Empty result (200)
```json
{ "items": [], "nextCursor": null, "total": 0 }
```

### Not found (404)
```json
{ "error": "not_found", "message": "Camera cam-999 not found" }
```

### Permission denied (403)
```json
{ "error": "forbidden", "message": "Insufficient permission for cameraGroupId group-5" }
```

### Invalid request (400)
```json
{ "error": "validation_failed", "field": "from", "message": "Invalid date format" }
```

### Unauthorized (401)
```json
{ "error": "unauthorized", "message": "Token expired" }
```

### Rate limited (429)
Headers: `Retry-After: 30`
```json
{ "error": "rate_limited", "retryAfterSeconds": 30 }
```
```
