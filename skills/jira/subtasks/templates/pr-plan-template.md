# PR Plan — \<STORY-ID\> \<story title\>

> Created by `/jira-subtasks` Step 1.5. Updated through Steps 4 and 7 as Jira IDs and PRs land. Confirm groupings with the user before any Jira tickets are created.

## Flow groups

A flow is a sequence of endpoints/screens a user actually walks through. Plumbing-only work (types, middleware, helpers) is not a flow — it groups under "foundation".

| Flow | Endpoints / behavior | Sub-tasks |
|---|---|---|
| Foundation | (no user-visible behavior) | T1, T3 |
| Login | /auth/login → /auth/login-respond → /auth/password-force-change | T4 |
| Session ops | /auth/refresh + /auth/logout + /auth/password-change | T5a |
| Forgot password | /auth/password-forgot → /auth/password-reset | T5b |

## PR sequence

| PR | Title prefix | Impl sub-tasks | uat sub-task | Refactor first | Depends on |
|---|---|---|---|---|---|
| 1/4 | `[STORY-ID 1/4] foundation + pentest fix` | T1, T3 | n/a (plumbing) | R1 | — |
| 2/4 | `[STORY-ID 2/4] login flow` | T4 | U2 | none | 1/4 |
| 3/4 | `[STORY-ID 3/4] session ops + ops` | T5a, T7 | U3 | none | 2/4 |
| 4/4 | `[STORY-ID 4/4] forgot password` | T5b | U4 | none | 1/4 |

After `/testing-write`, replace `U<n>` cells with `[VOR-XXXXX](https://vivotek.atlassian.net/browse/VOR-XXXXX)` links.

## Refactor PRs

R-rows land first as **no-op behavior** PRs, separate review, then the flow PR rebases on them. Mid-impl refactor smells = the flow PR is too big.

| Refactor PR | What | Lands before |
|---|---|---|
| R1 | Extract CognitoAuthService interface | 1/4 |

## Rules enforced by this plan

- **Title prefix `[STORY-ID N/M]`** — reviewer sees ordering immediately. (`/review-pr` Check A flags missing prefix.)
- **Demo unit per PR** — each row's flow column = the user-visible thing it ships. Plumbing-only PRs allowed only for "foundation" rows.
- **Refactor PRs land first**, no-op behavior, separate review.
- **Companion test PR exists and is RED** before impl PR is "ready for review". Impl turns it GREEN. Marked `n/a` only for plumbing or ops-only PRs.
- **Dependencies are explicit.** PR can be in parallel branches as long as its `Depends on` is merged.
- **Each PR ≤ 5 days estimate.** If a single PR exceeds budget, split further.

## Estimate aggregation

| PR | Sum of T-task + U-task estimates | Status |
|---|---|---|
| 1/4 | 2d (T1) + 0.5d (T3) = 2.5d | (in progress / merged) |
| 2/4 | 3d (T4) + 1d (U2) = 4d | |
| 3/4 | 2d (T5a) + 0.5d (T7) + 1d (U3) = 3.5d | |
| 4/4 | 1d (T5b) + 0.5d (U4) = 1.5d | |

Total: ~11.5d across 4 PRs. If any single PR exceeds **5 days**, return to Step 1.5 and split it.
