---
name: external
description: Use when a story has an unresolved third-party or external dependency. The deps subcommand documents what is known vs unknown, generates a provisional contract to unblock parallel development, and plans a mock provider. Prevents entire stories from being blocked by vendor delays.
---

# external

Handles incomplete third-party information so the team can keep working on
what they can, without pretending the spec is complete.

## Subcommands

| Slash command | What it does | Output |
|---|---|---|
| `/external-deps <STORY-ID>` | Document the dependency, generate provisional contract, plan mock provider. Merged: dependency-handler + provisional-contract-generator + mock-provider-planner. | `./docs/stories/<ID>-<slug>/external-deps.md` |

## When to use

Run when `audit-spec` or `repo-context-scan` reveals an unresolved external dependency:
- Third-party API schema not yet confirmed
- Vendor sandbox not yet available
- Webhook/callback format still changing
- External team hasn't delivered their interface yet

## Key rule (workflow spec §8)

```
Do not block the entire story on a third party.
Only block the actual integration tasks.
```

The `deps` subcommand produces a Jira task split that separates
"can start now" from "blocked on vendor" — so parallel development continues
while the external dependency is resolved.

## Adapter boundary pattern

All third-party integrations should be isolated:

```
Product logic
↓
Internal interface
↓
ThirdPartyAdapter
↓
Third-party API
```

This means third-party schema changes only affect the adapter, not the
product logic. The provisional contract defines the internal interface.
