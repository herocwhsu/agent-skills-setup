# review-pr skill

**Date:** 2026-05-29
**Status:** Approved (pending implementation)
**Owner:** repo maintainer

## Problem

PR reviews on the target repo have two recurring failure modes:

1. **Missed issues.** Reviewers focus on style nits while real bugs slip
   through and surface later as hotfixes or reverts.
2. **Noisy output.** When reviews do catch problems, they often arrive as
   long walls of comments that authors skim, miss the critical issue inside,
   and merge anyway.

The built-in Claude Code `/review` command is general-purpose and has no
context about what *this team's* past reviews missed or over-focused on.

## Goal

Build a skill that reviews new PRs using a playbook of patterns mined from
the repo's own closed PRs, and outputs a tight, focused message: top 3-5
issues max, ranked by severity, with file:line refs.

## Non-goals

- Auto-posting comments to PRs. The skill produces a *draft* comment and a
  full local report; the human reviews and posts manually.
- Inline line-by-line GitHub review comments. One summary comment only.
- Cross-repo playbook sharing. Each playbook is repo-specific; other repos
  build their own by re-running mining.
- Replacing human reviewers. The skill is a first-pass filter that surfaces
  candidates; humans make merge calls.

## Approach

Two slash commands, separate concerns:

- **`/mine-review-patterns [count]`** — runs once or quarterly. Scans closed
  PRs, extracts recurring patterns, writes `playbook.md` for human review.
- **`/review-pr <number>`** — runs per PR. Reads playbook + diff, produces
  a short PR comment draft and a full local report.

Why two commands instead of one with cached mining: mining is slow and
expensive (hundreds of `gh` calls + LLM analysis), reviewing should be
fast. Separating them also lets a human edit the playbook by hand — the
team's domain knowledge feeds back in.

## Architecture

```
agent-skills-setup/skills/review-pr/
├── SKILL.md
├── README.md
├── commands/
│   ├── mine-review-patterns.md     (slash-command instructions for Claude)
│   └── review-pr.md                (slash-command instructions for Claude)
├── assets/
│   ├── mining-system-prompt.md     (system prompt used during mining)
│   ├── review-system-prompt.md     (system prompt used during review)
│   └── playbook-template.md        (skeleton for empty playbook)
└── tests/
    ├── test_review_pr.sh           (bash glue tests)
    └── integration_review.sh       (opt-in real-API end-to-end)

<target-repo>/                      (target repo, not this skill repo)
└── .code-review/
    ├── playbook.md                 (committed; team curates)
    └── reviews/
        └── PR-<n>.md               (gitignored; per-review reports)
```

The slash commands themselves are Markdown files that Claude Code loads.
Claude executes the steps inside (`gh` calls, file reads, prompt
construction). No Python runtime required for the commands themselves.

**Prerequisite:** Run the commands from inside a local clone of the target
repo. Mining needs `git log` for hotfix detection. Review uses `gh pr diff`
(no clone strictly needed for diff data), but reuses the same cwd contract
for simplicity.

## The mining command

### Invocation

```
/mine-review-patterns [count]
```

`count` defaults to **50** (≈15 minutes of work). Higher counts available
for periodic re-runs (e.g., 200 quarterly).

### Steps Claude executes

1. Verify `gh auth status` succeeds. Abort with hint if not authenticated.
2. Verify `cwd` is inside a git repo with a configured `origin` remote.
   Abort with a hint if not.
3. Parse `<owner>/<repo>` from the origin URL and list closed PRs:
   `gh pr list --state closed --limit <count> --json number,title,body,mergedAt,files`
4. For each PR (batched in groups of 10 to fit context):
   - Fetch review comments: `gh api repos/<owner>/<repo>/pulls/<n>/comments --paginate`
   - Fetch top-level PR comments: `gh pr view <n> --json comments`
   - Look for hotfix/revert follow-ups in `git log` referencing the PR
     number or merge commit
5. Cluster the collected data into themes. The mining system prompt
   instructs the model to identify:
   - **Recurring issues** caught in review (top ~10, with example PR refs)
   - **Patterns reviewers missed** (caught later via hotfix/revert)
   - **Areas reviewers over-focused on** (style nits when bugs were
     present elsewhere)
   - **Domain-specific gotchas** (auth, billing, multi-tenant, migrations)
6. Write the result to `.code-review/playbook.md` and print a one-line
   summary. **Do not auto-commit.** The user reviews and commits manually.
7. On rate-limit or partial failure, save state to
   `.code-review/.mining-state.json` so a re-run resumes.

### Playbook format

```markdown
# <repo-name> code review playbook

_Last mined: 2026-05-29 (50 PRs)_

## Recurring issues (top 10)

### 1. Missing tenant_id filter on list queries
- Severity: critical
- Example PRs: #382, #401, #517
- How to spot: SQL or ORM query without `tenant_id = ?` in WHERE
- Why it matters: cross-tenant data leak
...

## Patterns reviewers missed
(Caught later via hotfix or revert)

### Race condition in license activation
- Original PR: #429 — merged 2026-02
- Hotfix PR: #441 — added Redis lock
- Lesson: any new endpoint that mutates licenses needs a lock check
...

## Reviewer over-focus
(Time spent on these did not prevent the real bugs)
- Naming style of test variables
- Whether to use early-return vs nested if
...

## Domain gotchas
- Region-routing quirks documented as anchored examples
- Idempotency conventions, key lengths, etc.
...
```

## The review command

### Invocation

```
/review-pr <pr-number>
```

### Steps Claude executes

1. Check `cwd` is a git repo with an `origin` remote. Abort if not.
2. Read `.code-review/playbook.md`. If missing, abort with:
   `"Run /mine-review-patterns first, or write .code-review/playbook.md by hand."`
3. Fetch PR data:
   - `gh pr view <n> --json title,body,files,headRefName,baseRefName,additions,deletions`
   - `gh pr diff <n>`
4. If `additions + deletions > 2000`, warn: "Large PR. Review may be
   noisy. Continue? (y/n)" and wait for user answer.
5. Send diff + playbook + PR metadata to the model with the review system
   prompt. Constraints encoded in the prompt:
   - Maximum 5 issues, ranked by severity
   - Severities: `critical` / `important` / `minor`
   - Each issue: one sentence + `file:line` ref + (optional) playbook
     pattern reference
   - If no critical or important issues found, say so explicitly. Do not
     pad with minors.
   - No preamble ("great work!"), no per-file walkthrough.
6. Write outputs:
   - **Full local report:** `.code-review/reviews/PR-<n>.md` — all
     findings, the model's reasoning, candidates filtered out
   - **Comment draft:** `.code-review/reviews/PR-<n>-comment.md` — top
     3-5 issues, ready to paste
7. Print to terminal:
   - The comment draft (so the user sees it inline)
   - The path to the full report
   - The exact `gh pr comment` command to post (not executed)

### Comment draft format

```markdown
## Review summary

<N> issues worth flagging. Full details: `.code-review/reviews/PR-<n>.md`

**Critical:**
- `auth/middleware.go:47` — missing tenant_id check, callers from /v1/admin can hit cross-tenant data. Matches playbook pattern #1.

**Important:**
- `services/billing.go:128` — error from `chargeCard` swallowed, returns nil.

**Minor:**
- `db/migrations/0042.sql` — no down migration. Team convention.
```

If only 1 issue, only 1 issue. No filler.

## Configuration

| Var | Default | Effect |
|---|---|---|
| `REVIEW_PR_PLAYBOOK` | `.code-review/playbook.md` | Playbook path |
| `REVIEW_PR_REPORT_DIR` | `.code-review/reviews` | Per-PR reports |
| `REVIEW_PR_MAX_DIFF_LINES` | `2000` | Large-PR warning threshold |
| `REVIEW_PR_MODEL` | `claude-sonnet-4-6` | Model for review (Sonnet has the judgment for code review; Haiku is too aggressive on minors) |

The owner/repo is derived from `git remote get-url origin` at run time —
no env var needed. All other values are optional. Defaults work for the
common case.

## Error handling

| Scenario | Behavior |
|---|---|
| `gh` not authenticated | Abort with `gh auth login` hint |
| Not in a git repo / no origin | Abort with cwd hint |
| Playbook missing during review | Abort with "run mining first" hint |
| Mining rate-limited mid-run | Save state to `.mining-state.json`, resume on next run |
| Review API fails | Print partial output + error, do not write a partial report file |
| PR has zero files changed | Print "PR has no changes; nothing to review" and exit 0 |
| PR not found / closed / private inaccessible | Print `gh` error verbatim and exit 1 |

## Testing

### Bash glue tests (`tests/test_review_pr.sh`)

Test the deterministic pieces:
- cwd validation logic
- Playbook path resolution with env override
- "Run mining first" message when playbook missing
- Large-PR threshold check

These do not hit the API. They use mocked `gh` and a temp working dir.

### Integration test (`tests/integration_review.sh`)

Opt-in via `RUN_INTEGRATION=1`. Runs `/review-pr` against a known closed
PR and asserts the output contains expected keywords. Burns tokens; CI
does not run by default.

### Manual validation

After install, the first real validation is running
`/mine-review-patterns 20` against the target repo and reading the
output. If patterns look correct, scale up to 50 or 100. The mining
quality is itself the test of the mining prompt.

## Install / uninstall

The skill is a `local`-type skill in `registry.txt`, so the standard
install picks it up automatically:

```
bash scripts/install.sh
```

No `--with-hook` flag — review-pr is not a hook, it's a slash-command
skill. No pip dependencies. Requires `gh` CLI (already required for
Claude Code GitHub workflows).

`scripts/uninstall.sh` removes the symlink as part of normal cleanup.
The target repo's `.code-review/` directory is left untouched (it's the
team's data, not the skill's).

## Migration / first-run

There's no existing review skill to migrate from. First-time setup:

1. Install: `bash scripts/install.sh --with-skill review-pr`
2. `cd /path/to/your/repo`
3. `mkdir -p .code-review/reviews` and add `reviews/` to `.gitignore`
4. Run `/mine-review-patterns 50`
5. Read `.code-review/playbook.md`, edit if needed
6. Commit the playbook
7. On future PRs: `/review-pr <number>`

## Rollout

Single-user skill, no staged rollout. Single PR adds the skill files,
docs, install entry. The team can adopt by running install themselves.

## Open questions

None. All decisions captured above.
