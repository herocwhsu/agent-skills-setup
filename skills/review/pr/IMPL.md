---
name: review-pr
slash: /review-pr <pr-number>
description: Use when the user wants a focused review of a specific PR. Reads `.code-review/playbook.md` plus the PR diff, produces a full local report and a short PR comment draft (not auto-posted). Argument is the PR number.
---

# review-pr

Review a single PR using the mined playbook. Output: a full local report
plus a 3-5 issue comment draft you post manually.

This skill is the entry point for the `/review-pr <number>` slash command.

## Prerequisites

- `gh` CLI authenticated.
- Current working directory is inside the target repo.
- `.code-review/playbook.md` exists (run `/mine-review-patterns` first).

## Inputs the review uses

The skill assembles three review references, in increasing specificity:

1. **Charter** (`charter.md` in this skill's directory) — the framework: priority order, severity prefixes, the "ask yourself" prompts. Bundled with the skill, same for every repo.
2. **Mined playbook** (`.code-review/playbook.md`) — repo-specific patterns anchored to real PR numbers. Required.
3. **Per-repo override** (`.code-review/REVIEWING.md`) — optional. If present, it's the team's own checked-in review charter, and it takes precedence over the bundled charter when they conflict.

## Workflow

The argument is the PR number. Required.

### Step 1 — Verify environment

```bash
gh auth status
git remote get-url origin
```

Same checks as `mine-review-patterns`. Abort with clear messages if either fails.

### Step 2 — Verify the playbook exists

If `.code-review/playbook.md` does not exist, tell the user:

```
.code-review/playbook.md not found. Run /mine-review-patterns first, or
write the playbook by hand. Aborting.
```

and stop.

### Step 3 — Prepare workspace

```bash
mkdir -p .code-review/reviews
```

Ensure `.gitignore` contains the following patterns (use the Edit tool to add any that are missing). These keep per-review reports and any temp files from accidentally landing in commits if cleanup fails mid-run:

```
.code-review/reviews/
.code-review/.mining-*.json
.code-review/.mining-state.json
.code-review/.pr-*.json
.code-review/.pr-*.diff
.code-review/.pr-*-comments.json
.code-review/.pr-*-prechecks.json
```

`.code-review/playbook.md` and any `.code-review/REVIEWING.md` are intentionally **not** gitignored — they're team artifacts meant to be committed.

### Step 4 — Fetch PR data

```bash
gh pr view <n> --json title,body,files,headRefName,baseRefName,additions,deletions,state,headRefOid > .code-review/.pr-<n>-meta.json
gh pr diff <n> > .code-review/.pr-<n>.diff
gh api "repos/{owner}/{repo}/pulls/<n>/comments" > .code-review/.pr-<n>-comments.json
```

If `gh` exits non-zero, print the error verbatim and stop.

### Step 4.5 — Deterministic pre-checks

Run two cheap checks before involving the model. Findings get appended to the report's "Pre-checks" section.

**Check A — Title prefix `[STORY-ID N/M]`**

PRs that belong to a multi-PR story must declare their position. Read `pr-plan.md` from `./docs/stories/<STORY-ID>-<slug>/` if present. If the PR's branch matches a `STORY-ID` referenced there:

```bash
title=$(jq -r .title .code-review/.pr-<n>-meta.json)
branch=$(jq -r .headRefName .code-review/.pr-<n>-meta.json)
# Story ID convention: branch name starts with the Jira ID
story_id=$(echo "$branch" | grep -oE '^[A-Z]+-[0-9]+')

# Run the prefix check inside `bash -c` to avoid zsh regex incompatibilities
# when this snippet is invoked from a non-bash shell.
if [[ -n "$story_id" ]] && ls docs/stories/${story_id}-*/pr-plan.md 2>/dev/null; then
  pattern="^\[${story_id} [0-9]+/[0-9]+\] "  # trailing space required after ]
  if ! bash -c "[[ \"\$1\" =~ \$2 ]]" _ "$title" "$pattern"; then
    echo "MISSING_TITLE_PREFIX: title \"$title\" does not start with [$story_id N/M]"
  fi
fi
```

If the story has only one PR (no `pr-plan.md` or the plan lists exactly one row), the prefix is optional. Flag only when the plan declares N>1.

**Check B — Stale review comments after force-push**

After a rebase the PR head SHA changes. GitHub keeps inline review comments anchored to the **old** commit, so reviewers see comments on code that no longer exists in that form. Identify these so the report can recommend "addressed in <new SHA>" replies or auto-resolution.

```bash
head_sha=$(jq -r .headRefOid .code-review/.pr-<n>-meta.json)
stale=$(jq --arg head "$head_sha" '
  [ .[] | select(.commit_id != $head) | {
      id, path, line,
      old_sha: (.commit_id[:8]),
      author: .user.login,
      excerpt: (.body[:80])
    } ]
' .code-review/.pr-<n>-comments.json)

stale_count=$(echo "$stale" | jq 'length')
if [[ "$stale_count" -gt 0 ]]; then
  echo "STALE_COMMENTS: $stale_count comments anchored to commits not at PR head ($head_sha)"
fi
```

Write the structured findings to `.code-review/.pr-<n>-prechecks.json` so the model can consume them in Step 7.

### Step 5 — Size guard

Read the metadata file and compute `additions + deletions`. If the total exceeds `2000` (or the value of `REVIEW_PR_MAX_DIFF_LINES` if set):

```
This PR changes <N> lines. Reviews of large PRs tend to be noisy. Continue? (y/n):
```

Wait for the user. If `n`, abort and clean up.

### Step 6 — Skip empty PRs

If the metadata `files` list is empty, tell the user `PR <n> has no file changes; nothing to review.` and stop. Do not write a report file.

### Step 7 — Run the review

1. Read the bundled charter: `charter.md` (in this skill's directory)
2. Read the mined playbook: `.code-review/playbook.md`
3. If `.code-review/REVIEWING.md` exists, read it too — this is the per-repo override and takes precedence over the bundled charter when they conflict.
4. Read pre-check findings: `.code-review/.pr-<n>-prechecks.json` from Step 4.5
5. Read the prompt: `review-prompt.md` (in this skill's directory)
6. Send to the model with the prompt as the system prompt:
   - Charter (or per-repo override if present)
   - Mined playbook
   - Pre-check findings (so the report cites them as `blocking:` for missing prefix and `important:` for stale-comment cleanup)
   - PR title + body + branch info
   - Unified diff
7. Use model `claude-sonnet-4-6` (override with `REVIEW_PR_MODEL` env var if set).
8. Receive two artifacts in the model's output: the full report and the comment draft.

### Step 8 — Write outputs

```bash
# full report
.code-review/reviews/PR-<n>.md

# comment draft (separate file so user can post directly)
.code-review/reviews/PR-<n>-comment.md
```

Do NOT auto-post the comment to the PR. Print to terminal:

```
Review written. Files:
  Full report:    .code-review/reviews/PR-<n>.md
  Comment draft:  .code-review/reviews/PR-<n>-comment.md

To post the comment:
  gh pr comment <n> --body-file .code-review/reviews/PR-<n>-comment.md
```

Print the comment draft inline below that message so the user can read it
without opening the file.

### Step 9 — Cleanup

```bash
rm .code-review/.pr-<n>-meta.json .code-review/.pr-<n>.diff .code-review/.pr-<n>-comments.json .code-review/.pr-<n>-prechecks.json
```
