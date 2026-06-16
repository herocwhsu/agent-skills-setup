---
subcommand: domain-risk
group: audit
slash: /audit-domain-risk <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/domain-risk.md
---

# audit/domain-risk — Domain Risk Check

Checks the story against a list of domain-specific risks that generic spec
audits miss. This is what makes agents aware of product-specific constraints
rather than acting like generic coding assistants.

Corresponds to workflow spec §14.2 skill 6 ("vortex-domain-risk-checker") but
intentionally generalized — the repo can inject its own check list.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

## Check list source (in priority order)

1. **Repo-local override**: `./.spec-gated/domain-risk-checks.md` in the
   target repo's root. If this file exists, use its checks instead of the
   built-in list. This is how teams add product-specific checks (e.g. camera
   group hierarchy, AI event accuracy, cloud recording impact).

2. **Built-in generic list** (fallback when no override exists):

| Risk area | Check questions |
|---|---|
| Tenant isolation | Does this feature access or expose data across tenants? Are all queries scoped to the authenticated tenant? |
| Permission / authorization | Are all actions gated by a permission check? Is the check at the right layer (API handler, not just UI)? Are permission-denied responses correct (403 not 404)? |
| Error behavior | Are all 4xx errors meaningful (not "400 Bad Request" without context)? Is 429 rate-limiting handled? Are 5xx errors logged with trace IDs? |
| Data retention / deletion | Does this feature create data? What is the retention policy? Is deletion of related entities handled (cascades)? |
| Audit log | Should this action be logged in an audit trail? Who can query the audit log? |
| Notification behavior | Does this trigger notifications? Is notification deduplication handled? Can users opt out? |
| Latency / bandwidth | Is this a high-volume endpoint? Is pagination required? Are large payloads compressed? |
| Failover / offline | What happens when a dependent service is unavailable? Is there a graceful degradation path? |
| Input validation | Are all external inputs validated at the system boundary? Is there a max length / size constraint? |
| Idempotency | For write operations: is the operation idempotent? Is there a risk of duplicate submission? |
| Browser auth (cookie/session) | If auth uses cookies: is `AllowCredentials: true` set in CORS for every cross-origin frontend in the allow-list? Are cookies `HttpOnly` + `Secure` + correct `SameSite` (Lax for top-level nav, None for cross-site iframes)? Is the cookie value the raw token (Bearer prefix added by middleware) so JS can never read a usable bearer? Is refresh-token rotation handled — old token blacklisted, new one set atomically? Does logout clear cookies AND blacklist the JTI server-side (not just delete client-side)? |

## How to run the check

For each risk area:

1. Read the story folder artifacts (`story.md`, `confluence-*.md`).
2. Apply each check question to the described feature.
3. Classify the outcome as: ✓ Addressed | ⚠ Partially addressed | ✗ Not addressed | N/A

If a risk is not addressed, decide:
- **Flag**: add it to the OpenSpec "Risks" section — this is most common.
- **Block**: if the risk is severe enough to invalidate the current design, mark it as a `must-resolve` (same classification as audit/spec gaps).

## Output format

Write to `$STORY_DIR/domain-risk.md`:

```markdown
---
story: <JIRA-ID>
checked_at: <YYYY-MM-DD>
check_source: repo-local | built-in
flagged_count: <n>
blocked_count: <n>
---

# Domain Risk Report: <JIRA-ID>

## Check Source
<repo-local path, or "built-in generic list">

## Risk Assessment

| Risk Area | Status | Notes |
|---|---|---|
| Tenant isolation | ✓ / ⚠ / ✗ / N/A | <brief note> |
| Permission / authorization | | |
| Error behavior | | |
| Data retention / deletion | | |
| Audit log | | |
| Notification behavior | | |
| Latency / bandwidth | | |
| Failover / offline | | |
| Input validation | | |
| Idempotency | | |
| Browser auth (cookie/session) | | |

## Flagged Risks (include in OpenSpec "Risks" section)

- **RISK-1**: <risk description>
  - *Area*: <risk area>
  - *Recommendation*: <what to add to the design>

## Blocked Items (must resolve before OpenSpec approval)

- **BLOCK-1**: <description>
  - *Why blocking*: <reason>

## Recommended Next Steps
- [ ] Add flagged risks to OpenSpec proposal under "Risks"
- [ ] Resolve any blocked items with PM / tech lead
- [ ] Run /audit-handoff <STORY-ID> when all blocks are resolved
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Skipping N/A items | Always record N/A explicitly so reviewers know the check was done |
| Flagging obvious things already in the spec | Only flag gaps and unknowns, not things already addressed |
| Blocking on risks that are low-severity | Reserve `blocked` for risks that invalidate the design, not for things to add to the spec |
