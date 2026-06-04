---
subcommand: deps
group: external
slash: /external-deps <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/external-deps.md
---

# external/deps — External Dependency Handler

Handles the situation where a feature cannot be fully specified because a
third-party vendor, external team, or partner has not finalized their part.

Merges three workflow spec skills (§14.5, skills 14–16):
- `external-dependency-handler` — lists what is known and unknown
- `provisional-contract-generator` — creates a provisional contract to unblock work
- `mock-provider-planner` — plans the mock/fake provider strategy

These always co-trigger. If you have an incomplete external dep, you need all three.

## When to run

Run this when `audit-spec` or `repo-context-scan` surfaces an unresolved
third-party dependency. Signs:
- The story references an external API whose schema is not yet confirmed
- A partner/vendor sandbox is not yet available
- A webhook format is still changing
- Third-party credentials/access are pending

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

## Step 1 — Identify the external dependency

Read `story.md`, `confluence-*.md`, and `audit-report.md`. Extract:
- Name of the external system / vendor
- What it provides (API, webhook, data feed, etc.)
- What is confirmed vs what is unknown
- What the blocking items are

## Step 2 — Document the dependency

For each external dependency:

```
Dependency: <name of external system>
Current status: <Pending confirmation / Sandbox not yet available / Schema changing>

Confirmed information:
- <what is definitely known>

Assumptions (if wrong, requires CR):
- <assumption 1>
- <assumption 2>

Unknowns:
- <unknown 1> — Question for: <vendor / PM / external team>
- <unknown 2>

Fallback plan:
- <what to build independently while waiting>
```

## Step 3 — Generate provisional contract

Create a best-guess interface that:
- Captures what the external system WILL likely provide
- Uses generic field names when specifics are unknown
- Isolates third-party schema behind an adapter boundary

Provisional contract example:

```
Provisional API Contract

Endpoint: POST /vendor/events (assumed)
Request: { tenantId: string, eventType: string }
Response: { id: string, status: "accepted" | "rejected", ... }

NOTE: This is provisional. Final schema pending vendor confirmation.
Adapter: VendorEventAdapter — isolates schema from product logic.
```

## Step 4 — Plan mock provider

Plan a mock/fake provider that:
- Simulates the external system's behavior during development
- Covers happy path, error responses, and latency simulation
- Enables contract tests before the real system is available

Mock plan template:

```
Mock Provider Plan

Mock endpoint: <local or test double>
Fake responses:
  - Success: { ... }
  - Error (4xx): { error: "...", code: ... }
  - Timeout: delay 5000ms, no response
  - Rate limited: 429 + Retry-After header

Contract test cases:
  1. Happy path — valid request → expected success response
  2. Auth failure — missing/invalid token → 401
  3. Vendor unavailable — timeout → graceful degradation
```

## Jira task split rule (workflow spec §8)

Never block the entire story on a third party. Split tasks:

| Task | Status |
|---|---|
| Define provisional integration contract | Can start |
| Build internal adapter interface | Can start |
| Build mock / fake provider | Can start |
| Implement feature behind feature flag | Can start |
| Confirm final third-party API schema | Blocked |
| Integrate with third-party sandbox | Blocked |
| Run contract verification | Blocked |
| Production readiness review | Blocked |

## Output format

Write to `$STORY_DIR/external-deps.md`:

```markdown
---
story: <JIRA-ID>
created_at: <YYYY-MM-DD>
blocking_count: <n>
---

# External Dependencies: <JIRA-ID>

## Dependencies

### <Vendor/System Name>
[dependency doc from Step 2]

## Provisional Contract
[contract from Step 3]

## Mock Provider Plan
[plan from Step 4]

## Jira Task Split
[table from Step 4 rule]

## Adapter Boundary
Product logic → Internal interface → <VendorName>Adapter → <Vendor> API

This isolates third-party schema changes from the core product.
```
