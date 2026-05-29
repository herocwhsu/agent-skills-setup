---
name: mine-review-patterns
description: Use when the user wants to (re)build the code-review playbook for a target repo. Scans closed PRs, extracts recurring issues, missed patterns, reviewer over-focus, and domain gotchas into `.code-review/playbook.md`. Run from inside the target repo. Optional argument is the PR count to scan (default 50).
---

# mine-review-patterns

Scan closed PRs in the current repo to produce `.code-review/playbook.md` —
a curated reference future PR reviews consult.

This skill is the entry point for the `/mine-review-patterns` slash command.
The full instructions live in this file; Claude follows them step by step.

## Prerequisites

- `gh` CLI authenticated (`gh auth status` succeeds).
- Current working directory is inside a clone of the target repo.
- Repo has closed PRs to mine.

## Workflow

Read this entire workflow before starting. Default PR count is 50; if the
user supplied an argument, use that. The argument is the only argument.

### Step 1: Verify environment

Run these checks. Abort with a clear message on any failure.

```bash
gh auth status
git remote get-url origin
```

If `gh auth status` fails: tell the user `Run "gh auth login" first` and stop.

If `git remote get-url origin` fails: tell the user `cd into the target repo first` and stop. Otherwise parse `<owner>/<repo>` from the origin URL and use it for all subsequent `gh` calls — the skill is repo-agnostic.

### Step 2: Prepare output directory

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
```

`.code-review/playbook.md` is intentionally **not** gitignored — it's a team artifact meant to be committed.

### Step 3: Fetch closed PRs

```bash
gh pr list --state closed --limit <count> --json number,title,body,mergedAt,files,baseRefName,headRefName > .code-review/.mining-prs.json
```

Read the JSON. If the list is empty, tell the user `No closed PRs found` and stop.

### Step 4: Fetch comments for each PR (batched)

For each PR in the list (process in batches of 10 to keep context size manageable):

```bash
gh api "repos/{owner}/{repo}/pulls/<n>/comments" --paginate > .code-review/.mining-comments-<n>.json
gh pr view <n> --json comments > .code-review/.mining-toplevel-<n>.json
```

Where `{owner}/{repo}` is parsed from the origin URL.

### Step 5: Detect hotfixes / reverts

For each merged PR, search `git log` on the default branch for commits that mention the PR number or the merge commit:

```bash
git log --since="<merged-at-of-PR>" --grep="#<n>" --grep="revert" --grep="hotfix" --pretty=format:"%h %s"
```

Record any matching commits as potential follow-ups. Read the matched commit messages to confirm they're actually hotfixes for this PR (not coincidental mentions).

### Step 6: Cluster and summarize

For each batch of 10 PRs:

1. Read the prompt at `~/.claude/skills/mine-review-patterns/mining-prompt.md`.
2. Send the batch (PR data + comments + hotfix matches) to the model with that prompt as the system prompt. Use `claude-sonnet-4-6` for the analysis (Haiku is too aggressive on patterns; Opus is overkill).
3. Append the batch's findings to a running list in memory.

After all batches: send the consolidated findings to the model once more, with the same prompt, asking it to deduplicate and rank. Output is the final playbook markdown.

### Step 7: Write the playbook

Write the final markdown to `.code-review/playbook.md`. Add a header line:

```
_Last mined: <date> (<count> PRs scanned)_
```

DO NOT auto-commit. Print:

```
Wrote .code-review/playbook.md (<count> PRs scanned, <N> patterns).
Review and edit, then commit when ready.
```

### Step 8: Cleanup

```bash
rm .code-review/.mining-*.json
```

If mining failed mid-run (rate limit, network), keep `.code-review/.mining-state.json` with `{"completed_prs": [list]}` so a re-run resumes from where it stopped.
