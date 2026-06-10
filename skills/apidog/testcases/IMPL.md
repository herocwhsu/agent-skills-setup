---
subcommand: testcases
group: apidog
slash: /apidog-testcases <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/apidog/testcases.md
---

# apidog/testcases — API Test Case Generator

Generates API test cases from the contract and acceptance criteria.
Covers positive, negative, boundary, permission, and pagination cases.

Corresponds to workflow spec §14.7, skill 22 (apidog-testcase-generator).

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
STORY_DIR=$(resolve_story_dir "$1") || exit 1
[[ -f "$STORY_DIR/apidog/contract.md" ]] || { echo "ERROR: run /apidog-contract first" >&2; exit 1; }
```

Also read `./openspec/changes/<change-id>/specs/` for acceptance scenarios if
the directory exists.

## Test case categories

For each endpoint, generate test cases in each applicable category:

### Positive cases
- Happy path with all required fields
- Optional fields included
- Minimum valid input
- Maximum valid input

### Negative cases
- Missing required field → 400
- Wrong field type → 400
- Empty string where non-empty required → 400
- Invalid enum value → 400

### Boundary cases
- Pagination: first page, last page, page beyond end
- Date range: start = end, start > end
- Numeric limits: 0, max-1, max, max+1

### Permission cases
- Unauthenticated request → 401
- Wrong token → 401
- Valid token, no permission → 403
- Valid token, correct permission → 200
- Valid token, permission for different tenant → 403 or 404

### Compatibility cases
- Request with unknown extra fields (should ignore, not 400)
- Response has new fields added (client should handle gracefully)

## Output format

Write to `$STORY_DIR/apidog/testcases.md` and then push to Apidog (Step 2):

```markdown
---
story: <JIRA-ID>
created_at: <YYYY-MM-DD>
endpoint_count: <n>
testcase_count: <n>
---

# API Test Cases: <JIRA-ID>

## <Method> <Path>

### TC-001: Happy path — valid request returns paginated results
- **Category:** Positive
- **Given:** Authenticated user with camera read permission
- **When:** GET /api/v1/cameras/cam-123/events?limit=10
- **Then:** 200, items array, nextCursor present if more results

### TC-002: Missing auth token
- **Category:** Permission
- **Given:** No Authorization header
- **When:** GET /api/v1/cameras/cam-123/events
- **Then:** 401

### TC-003: Permission for different tenant's camera
- **Category:** Permission
- **Given:** Valid token for tenant-A, cameraId belongs to tenant-B
- **When:** GET /api/v1/cameras/cam-tenant-b/events
- **Then:** 403 or 404 (confirm which with security review)

[... additional test cases ...]

## Coverage Summary
| Category | Count |
|---|---|
| Positive | |
| Negative | |
| Boundary | |
| Permission | |
| Compatibility | |
| **Total** | |
```

## Step 2 — Push to Apidog via MCP

After the local file is written, push test cases to Apidog:

```
apidog_create_cases(
  cases: [
    {
      endpoint: "<METHOD> <path>",
      name: "TC-001: Happy path",
      request: { ... },
      expectedResponse: { status: 200 }
    },
    // ... one entry per test case
  ],
  module: <module-name>
)
```

On success, print:
```
Test cases pushed to Apidog.
```

On failure, print the MCP error verbatim. The local markdown file remains
as the source of truth.

## MCP prerequisite check

Before Step 2, verify MCP is available:

```
apidog_modules()
```

If this fails, tell the user to run `/infra-apidog-mcp setup` first.
