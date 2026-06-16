---
subcommand: write
group: testing
slash: /testing-write <STORY-ID>
output: Jira U<n> sub-task(s) + RED test stubs in the test repo + updated pr-plan.md
---

# testing/write — Companion Test Sub-task & RED Stub Creator

Creates the **U\<n\>** companion sub-task in the test repo's Jira project and scaffolds RED test stubs there. Each U\<n\> matches a flow PR group from `pr-plan.md`. Impl PR turns the stubs GREEN.

Workflow spec §16: "Endpoint-shipping PR is not done until its companion API test exists and is green."

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1

[[ -f "$STORY_DIR/pr-plan.md" ]]   || { echo "ERROR: pr-plan.md missing — run /jira-subtasks first" >&2; exit 1; }
[[ -f "$STORY_DIR/test-plan.md" ]] || { echo "ERROR: test-plan.md missing — run /testing-plan first" >&2; exit 1; }
[[ -z "${JIRA_HOST:-}" ]] && { echo "ERROR: JIRA_HOST not set" >&2; exit 1; }
[[ -z "${JIRA_USER:-}" ]] && { echo "ERROR: JIRA_USER not set" >&2; exit 1; }
```

The **test repo's project key** is asked interactively per story — different test repos may live in different Jira projects. Common pattern:

| Impl repo | Test repo | Likely project key |
|---|---|---|
| reseller-backend | reseller-uat | same `JIRA_PROJECT_KEY` (VOR) |
| webtech-monorepo | webtech-monorepo/e2e | same `JIRA_PROJECT_KEY` |
| service-A | service-A-tests (separate repo) | varies |

## Workflow

### Step 1 — Read PR plan and identify U-task rows

Parse `pr-plan.md`. For each PR row where the `uat sub-task` column is **not** `n/a`, queue a U\<n\> creation. Skip rows marked `n/a (plumbing)` — those have no companion test PR by design.

Present the queued list to the user for confirmation:

```
Will create U-task(s) for:
  U2 — PR 2/4 [STORY-ID 2/4] login flow      → reseller-uat, project VOR
  U3 — PR 3/4 [STORY-ID 3/4] session ops     → reseller-uat, project VOR
  U4 — PR 4/4 [STORY-ID 4/4] forgot password → reseller-uat, project VOR

Plumbing PRs (no U-task): 1/4
Confirm test repo path and Jira project key:
  Test repo: ~/Project/reseller-uat
  Jira project: VOR
```

Abort if the user changes test repo or project key — re-prompt rather than guess.

### Step 2 — Create U\<n\> Jira sub-task per flow PR

Each U\<n\> is a sub-task of the **parent story** (same `STORY_ID` as the impl T-tasks), not of the impl summary sub-task. This keeps the parent story's sub-task list flat and reviewable.

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER") || exit 1

ACCOUNT_ID=$(curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  "https://$JIRA_HOST/rest/api/2/myself" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)[\"accountId\"])")

create_u_task() {
  local pr_group="$1"          # e.g. "2/4"
  local summary="$2"           # e.g. "reseller-uat — SRP login + force-change cookie flow tests"
  local impl_subtask_ids="$3"  # e.g. "T4"
  local estimate="$4"          # e.g. "1d"
  local test_project="$5"      # e.g. "VOR"

  local description="Companion test sub-task for PR $pr_group. Covers impl sub-task(s): $impl_subtask_ids. Tests live in the test repo and start RED; impl PR turns them GREEN before requesting review."

  curl -s -u "$JIRA_USER:$_JIRA_PASS" \
    -X POST -H "Content-Type: application/json" \
    "https://$JIRA_HOST/rest/api/2/issue" \
    -d "{
      \"fields\": {
        \"project\":      {\"key\": \"$test_project\"},
        \"parent\":       {\"key\": \"$STORY_ID\"},
        \"issuetype\":    {\"name\": \"Sub-task\"},
        \"summary\":      \"$summary\",
        \"description\":  \"$description\",
        \"assignee\":     {\"accountId\": \"$ACCOUNT_ID\"},
        \"timetracking\": {\"originalEstimate\": \"$estimate\"}
      }
    }" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('key', f'ERROR: {d.get(\"errorMessages\", d)}'))
"
}

unset _JIRA_PASS
```

**Same JSON-escaping rules as `/jira-subtasks`:** no unescaped double quotes in summary or description, keep descriptions concise, use `timetracking.originalEstimate` (string), assignee = `accountId`.

### Step 3 — Scaffold RED test stubs in the test repo

For each created U\<n\>, write test scaffolds in the test repo. The skill does NOT pick test framework or naming — it reads from the test repo's existing patterns.

```bash
TEST_REPO="$2"   # path supplied at Step 1
cd "$TEST_REPO"

# Discover the existing test pattern. Try in order:
#   1. apitest/e2e/<feature>/    (Go, e.g. reseller-uat)
#   2. e2e/<app>/specs/          (Playwright, e.g. webtech-monorepo)
#   3. tests/<feature>/          (generic fallback)
# If multiple patterns exist, ask the user which one applies to this U-task.
```

For each U\<n\>:

1. Create a new file (or append to existing) named after the flow:
   - Login flow → `apitest/e2e/auth/login_test.go` (or matching pattern)
   - Session ops → `apitest/e2e/auth/session_test.go`
   - Forgot password → `apitest/e2e/auth/forgot_password_test.go`
2. Write **failing test stubs** — one per acceptance criterion in `test-plan.md` for that flow. Tests should:
   - Compile / parse cleanly
   - Fail with a clear "not yet implemented" message (e.g. `t.Skip("U2: pending impl in PR 2/4 — VOR-XXXXX")` or an explicit `t.Fatal("RED: contract not yet shipped")`)
   - Reference the U\<n\> Jira ID and PR group in a comment header
3. Create a feature branch in the test repo: `U<n>-<short-flow-name>` (e.g. `U2-login-flow`).
4. Commit the stubs with a short message: `test: add RED stubs for U<n> (PR <group>)`.
5. Push the branch — do NOT open the PR yet. The test repo PR is opened by the human reviewer or by `/jira-evidence` when impl is ready.

**Why RED, not GREEN-by-mock:** the contract isn't validated until real impl runs the test. Mocked GREEN tests give false confidence and hide spec drift.

### Step 4 — Update pr-plan.md with created U\<n\> Jira IDs

Open `$STORY_DIR/pr-plan.md` and replace placeholder `U<n>` cells with linked Jira IDs:

```markdown
| 2/4 | [STORY-ID 2/4] login flow | T4 | [VOR-XXXXX](https://vivotek.atlassian.net/browse/VOR-XXXXX) | none | 1/4 |
```

Also append the U\<n\> rows to `jira-subtasks.md` so it stays in sync:

```markdown
| U2 | [VOR-XXXXX](https://vivotek.atlassian.net/browse/VOR-XXXXX) | 2/4 | reseller-uat — SRP login + force-change cookie flow tests |
```

### Step 5 — Print handoff summary

```
Created:
  U2 (VOR-XXXXX) — branch reseller-uat:U2-login-flow — 4 RED test stubs
  U3 (VOR-XXXXX) — branch reseller-uat:U3-session-ops — 3 RED test stubs
  U4 (VOR-XXXXX) — branch reseller-uat:U4-forgot-password — 2 RED test stubs

Next:
  - Impl PR for each flow group must turn its U-task tests GREEN before "ready for review".
  - Impl PR description must contain: "Companion test PR: <test-repo>#NN (green)".
  - Open test repo PR after impl branch passes the U-task tests locally.
```

## When NOT to create a U-task

- PR group is **plumbing-only** (no user-visible behavior). The impl repo's unit tests are sufficient. Mark `n/a (plumbing)` in `pr-plan.md` with a one-line justification.
- PR group is **observability/ops only** (e.g. T7 = logging + runbook). API-test cannot meaningfully assert on log lines. Document this as `n/a (ops)`.
- PR group is a **pure refactor** (R\<n\> row). Existing tests must continue to pass; no new tests needed unless behavior actually changes.

If a PR group's behavior is genuinely covered by impl-repo tests AND there is no cross-repo contract surface, `n/a (covered by unit tests)` is acceptable. Reviewer of `/jira-subtasks` Step 1.5 should challenge this — most flow PRs have a test surface.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Creating GREEN-by-mock tests instead of RED | Tests must fail until impl ships. Mocks hide spec drift. |
| Putting U\<n\> as a sub-task of the impl summary, not the parent story | U\<n\> is a peer of T\<n\>, both nested directly under STORY-ID |
| Opening the test repo PR before impl branch is ready | Test PR opens after impl branch makes tests GREEN locally. RED stubs sit on a feature branch in the test repo, no PR yet. |
| Skipping U-task creation for "small" flow PRs | The size threshold is whether the contract is cross-repo, not LoC. Even a 1-endpoint PR needs a U-task if a test repo exists. |
| Hard-coding the test repo path | Ask interactively per story; different test repos live in different places. |
| Reusing one U-task for multiple flow PRs | One U\<n\> per PR group. Each PR has its own RED→GREEN proof. |
