# review-pr Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two slash-command skills — `mine-review-patterns` and `review-pr` — that mine the target repo's closed PRs into a playbook, then use the playbook to produce focused reviews on new PRs.

**Architecture:** Two registry-installed `local` skills, each is a single `SKILL.md` containing instructions Claude executes (gh CLI calls, file reads, model invocation). No Python runtime; no install dependencies beyond `gh`. Playbook + reports live under `.code-review/` in the target repo.

**Tech Stack:** Markdown SKILL.md files, bash test glue, `gh` CLI, Claude Code's Skill loader.

**Spec:** `docs/superpowers/specs/2026-05-29-pr-review-skill-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `skills/mine-review-patterns/SKILL.md` | **Create** | Slash-command instructions: scan closed PRs, produce `.code-review/playbook.md`. |
| `skills/mine-review-patterns/mining-prompt.md` | **Create** | Reference prompt the SKILL.md tells Claude to load when summarizing batches. |
| `skills/mine-review-patterns/tests/test_mining.sh` | **Create** | Bash test for the deterministic glue (cwd check, missing-gh detection, output paths). |
| `skills/review-pr/SKILL.md` | **Create** | Slash-command instructions: read playbook + diff, produce report + comment draft. |
| `skills/review-pr/review-prompt.md` | **Create** | Reference prompt for the review LLM call. |
| `skills/review-pr/tests/test_review.sh` | **Create** | Bash test for the deterministic glue. |
| `skills/review-pr/README.md` | **Create** | User-facing install + usage docs. |
| `skills/mine-review-patterns/README.md` | **Create** | User-facing install + usage docs. |
| `registry.txt` | **Modify** | Add two `local` entries. |

Each SKILL.md is the entry point for its slash command. The `*-prompt.md` files are referenced by the SKILL.md (Claude is told to read them before invoking the model). Splitting prompts out keeps SKILL.md readable and lets the prompts evolve independently.

---

## Task 1: Scaffold both skills with placeholder SKILL.md

**Files:**
- Create: `skills/mine-review-patterns/SKILL.md`
- Create: `skills/review-pr/SKILL.md`
- Modify: `registry.txt`

- [ ] **Step 1: Create the mining skill scaffold**

Create `skills/mine-review-patterns/SKILL.md`:

```markdown
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

(Filled in by Task 2.)
```

Create `skills/review-pr/SKILL.md`:

```markdown
---
name: review-pr
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

## Workflow

(Filled in by Task 4.)
```

- [ ] **Step 2: Register both skills**

Edit `registry.txt` to add two entries before the existing `local polish-input` line, in alphabetical order with the other `local` skills:

```
local  mine-review-patterns
local  review-pr
```

- [ ] **Step 3: Verify install picks them up (dry run)**

Run: `bash -n <repo-root>/agent-skills-setup/scripts/install.sh`
Expected: no syntax errors. (We don't actually install yet; that comes after the SKILL.md content is real.)

- [ ] **Step 4: Commit**

```bash
cd <repo-root>/agent-skills-setup
git add skills/mine-review-patterns/SKILL.md skills/review-pr/SKILL.md registry.txt
git commit -m "feat(review-pr): scaffold mining and review skills"
```

---

## Task 2: Fill in mining SKILL.md and prompt

**Files:**
- Modify: `skills/mine-review-patterns/SKILL.md`
- Create: `skills/mine-review-patterns/mining-prompt.md`

- [ ] **Step 1: Write the mining prompt asset**

Create `skills/mine-review-patterns/mining-prompt.md`:

```markdown
You are analyzing closed pull requests from a single repository to produce a
code-review playbook. Your output is a markdown document that future
reviewers will use as a checklist when reviewing new PRs.

You will receive a batch of PR data. Each PR includes:
- title, description
- list of files changed
- review comments (line-level and top-level)
- any follow-up commits or PRs that referenced it (hotfixes, reverts)

Your job is to identify and structure four kinds of patterns:

## 1. Recurring issues caught in review
Issues reviewers flag repeatedly. Cluster by root cause, not by file. For
each cluster: a short name, severity (critical / important / minor), one-
sentence description of how to spot it, and 2-3 example PR numbers.

## 2. Patterns reviewers missed
Issues that slipped through the original review and were caught later via
hotfix, revert, or follow-up PR. For each: original PR, follow-up PR, the
specific lesson reviewers should take from it.

## 3. Reviewer over-focus
Categories where reviewers spent significant time but the discussion did
not prevent real bugs. Style nits, naming bikeshedding, etc. Keep this
section short — these are anti-patterns the playbook should *de-emphasize*.

## 4. Domain gotchas
Repo-specific rules that aren't obvious from reading code. Cross-tenant
boundaries, regional routing quirks, idempotency conventions, migration
norms. Each gotcha cites the PR where the rule became explicit.

## Output rules

- No preamble. Start directly with `# <repo-name> code review playbook`.
- Cite PR numbers as `#NNN`, never as URLs.
- If a category has no patterns in the data, write `_(no patterns found in this batch)_` rather than padding.
- Maximum 10 entries per section. If you have more candidates, keep only the most frequent or highest-severity.
- One sentence per pattern in the "how to spot" line. No paragraphs.
```

- [ ] **Step 2: Fill in the mining workflow**

Replace the `## Workflow` section in `skills/mine-review-patterns/SKILL.md` with:

````markdown
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

If `.gitignore` does not contain `.code-review/reviews/`, add it (use the Edit tool).

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

Delete the temp files: `rm .code-review/.mining-*.json`.

If mining failed mid-run (rate limit, network), keep `.code-review/.mining-state.json` with `{"completed_prs": [list]}` so a re-run resumes from where it stopped.
````

- [ ] **Step 3: Verify the SKILL.md is well-formed**

Read the file back. Check:
- Frontmatter has `name` and `description`
- Workflow has 8 numbered steps
- All bash blocks use proper fenced syntax
- Links to the prompt file are correct path

- [ ] **Step 4: Commit**

```bash
cd <repo-root>/agent-skills-setup
git add skills/mine-review-patterns/SKILL.md skills/mine-review-patterns/mining-prompt.md
git commit -m "feat(review-pr): mining skill workflow and prompt"
```

---

## Task 3: Mining bash glue test

**Files:**
- Create: `skills/mine-review-patterns/tests/test_mining.sh`

This task tests the deterministic pieces (env validation, output paths, missing-prereq messages) using a mocked `gh`. It does NOT exercise the LLM path.

- [ ] **Step 1: Write the failing test**

Create `skills/mine-review-patterns/tests/test_mining.sh`:

```bash
#!/usr/bin/env bash
# Tests the deterministic glue from mine-review-patterns SKILL.md.
# These exercise the bash commands embedded in the workflow against a
# fake repo + fake `gh` to verify error messages and output paths.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: gh auth failure surfaces a clear message ---

mkdir "$TMP/repo1"
cd "$TMP/repo1"
git init -q
git remote add origin https://github.com/example/sample-repo.git

# fake gh that simulates auth failure
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  echo "You are not logged into any GitHub hosts." >&2
  exit 1
fi
exit 0
EOF
chmod +x "$TMP/bin/gh"
PATH="$TMP/bin:$PATH"

# Simulate the workflow's env-check
if gh auth status 2>/dev/null; then
  echo "FAIL: expected gh auth status to fail in test 1"
  exit 1
fi
echo "OK: gh auth failure detected"

# --- Test 2: missing origin is rejected ---

mkdir "$TMP/repo2"
cd "$TMP/repo2"
git init -q
# no remote configured

if git remote get-url origin 2>/dev/null; then
  echo "FAIL: test 2 unexpectedly found an origin"
  exit 1
fi
echo "OK: missing origin rejected"

# --- Test 3: output directory creation is idempotent ---

mkdir "$TMP/repo3"
cd "$TMP/repo3"
mkdir -p .code-review/reviews
mkdir -p .code-review/reviews  # second time should not fail
[ -d .code-review/reviews ] || { echo "FAIL: test 3 dir not created"; exit 1; }
echo "OK: output dir created idempotently"

echo ""
echo "All mining glue tests passed."
```

Make it executable:

```bash
chmod +x skills/mine-review-patterns/tests/test_mining.sh
```

- [ ] **Step 2: Run it to verify it passes**

Run: `bash skills/mine-review-patterns/tests/test_mining.sh`
Expected: three `OK:` lines and `All mining glue tests passed.`

- [ ] **Step 3: Lint-check**

Run: `bash -n skills/mine-review-patterns/tests/test_mining.sh`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
cd <repo-root>/agent-skills-setup
git add skills/mine-review-patterns/tests/test_mining.sh
git commit -m "test(review-pr): mining bash glue tests"
```

---

## Task 4: Fill in review SKILL.md and prompt

**Files:**
- Modify: `skills/review-pr/SKILL.md`
- Create: `skills/review-pr/review-prompt.md`

- [ ] **Step 1: Write the review prompt asset**

Create `skills/review-pr/review-prompt.md`:

```markdown
You are reviewing a single pull request. Output two artifacts:

1. A **full report** documenting every finding, including ones you decide
   not to promote. Format: markdown.
2. A **comment draft** with at most 5 issues, ranked by severity. Format:
   the exact markdown shown below.

You will receive: the playbook (the team's curated review checklist), the
PR title and description, and the unified diff.

## Constraints

- Maximum 5 issues in the comment draft. If you have more candidates, keep
  the highest-severity. Never pad with minors.
- Severities: `critical` (will break production or leak data), `important`
  (will cause a real bug or future incident), `minor` (style, convention,
  small inefficiency).
- Each issue in the comment draft is exactly one sentence + a `file:line`
  reference. If a playbook pattern matches, append `(matches playbook
  pattern: <short name>)`.
- If you find no critical or important issues, the comment draft is:
  `> No critical or important issues. <N> minor notes in the full report.`
  Do NOT pad with minors to fill space.
- No "great work!" preambles, no per-file walkthroughs, no praise.

## Comment draft format

```markdown
## Review summary

<N> issues worth flagging. Full details: `.code-review/reviews/PR-<n>.md`

**Critical:**
- `path/to/file.ext:LINE` — one-sentence description.

**Important:**
- `path/to/file.ext:LINE` — one-sentence description.

**Minor:**
- `path/to/file.ext:LINE` — one-sentence description.
```

Omit any section that has no entries. If all sections are empty, use the
"no critical or important issues" form above.

## Full report format

```markdown
# PR <n> review

**Title:** <PR title>
**Branch:** <head> → <base>

## Summary

<2-3 sentences: what this PR does, your overall take.>

## Findings

For each finding (including the ones promoted to the comment draft):

### <severity>: <short name>
- **Where:** `file:line`
- **What:** <2-3 sentences.>
- **Why it matters:** <1-2 sentences.>
- **Playbook match:** <pattern name, or "none">

## Candidates considered but filtered out

For each: short name, file:line, why you decided not to flag it. This
keeps your filtering visible to the human reviewer.
```
```

- [ ] **Step 2: Fill in the review workflow**

Replace the `## Workflow` section in `skills/review-pr/SKILL.md` with:

````markdown
## Workflow

The argument is the PR number. Required.

### Step 1: Verify environment

```bash
gh auth status
git remote get-url origin
```

Same checks as `mine-review-patterns`. Abort with clear messages if either fails.

### Step 2: Verify the playbook exists

If `.code-review/playbook.md` does not exist, tell the user:

```
.code-review/playbook.md not found. Run /mine-review-patterns first, or
write the playbook by hand. Aborting.
```

and stop.

### Step 3: Fetch PR data

```bash
gh pr view <n> --json title,body,files,headRefName,baseRefName,additions,deletions,state > .code-review/.pr-<n>-meta.json
gh pr diff <n> > .code-review/.pr-<n>.diff
```

If `gh` exits non-zero, print the error verbatim and stop.

### Step 4: Size guard

Read the metadata file and compute `additions + deletions`. If the total exceeds `2000` (or the value of `REVIEW_PR_MAX_DIFF_LINES` if set):

```
This PR changes <N> lines. Reviews of large PRs tend to be noisy. Continue? (y/n):
```

Wait for the user. If `n`, abort and clean up.

### Step 5: Skip empty PRs

If the metadata `files` list is empty, tell the user `PR <n> has no file changes; nothing to review.` and stop. Do not write a report file.

### Step 6: Run the review

1. Read the playbook: `.code-review/playbook.md`
2. Read the prompt: `~/.claude/skills/review-pr/review-prompt.md`
3. Send to the model with the prompt as the system prompt:
   - The playbook
   - The PR title + body + branch info
   - The unified diff
4. Use model `claude-sonnet-4-6` (override with `REVIEW_PR_MODEL` env var if set).
5. Receive two artifacts in the model's output: the full report and the comment draft.

### Step 7: Write outputs

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

### Step 8: Cleanup

```bash
rm .code-review/.pr-<n>-meta.json .code-review/.pr-<n>.diff
```
````

- [ ] **Step 3: Verify SKILL.md format**

Read the file back, confirm:
- Frontmatter present with `name` and `description`
- Workflow has 8 numbered steps
- The user-facing print message in step 7 is exact (the user will paste the gh command literally)

- [ ] **Step 4: Commit**

```bash
cd <repo-root>/agent-skills-setup
git add skills/review-pr/SKILL.md skills/review-pr/review-prompt.md
git commit -m "feat(review-pr): review skill workflow and prompt"
```

---

## Task 5: Review bash glue test

**Files:**
- Create: `skills/review-pr/tests/test_review.sh`

- [ ] **Step 1: Write the test**

Create `skills/review-pr/tests/test_review.sh`:

```bash
#!/usr/bin/env bash
# Tests the deterministic glue from review-pr SKILL.md.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: missing playbook produces clear error ---

mkdir "$TMP/repo1"
cd "$TMP/repo1"
git init -q

# Simulate the workflow's playbook check
if [[ -f .code-review/playbook.md ]]; then
  echo "FAIL: test 1 unexpectedly found a playbook"
  exit 1
fi
echo "OK: missing playbook detected"

# --- Test 2: large-PR threshold check ---

# Simulate the additions+deletions computation
additions=1500
deletions=600
total=$((additions + deletions))
threshold=${REVIEW_PR_MAX_DIFF_LINES:-2000}

if [[ "$total" -le "$threshold" ]]; then
  echo "FAIL: test 2 expected total $total to exceed threshold $threshold"
  exit 1
fi
echo "OK: large-PR threshold triggered ($total > $threshold)"

# Below threshold should pass through
additions=100
deletions=50
total=$((additions + deletions))
if [[ "$total" -gt "$threshold" ]]; then
  echo "FAIL: test 2b small PR wrongly flagged as large"
  exit 1
fi
echo "OK: small PR not flagged"

# --- Test 3: empty files list = skip review ---

# Simulate parsing the metadata file
mkdir -p "$TMP/repo1/.code-review"
echo '{"files":[]}' > "$TMP/repo1/.code-review/.pr-1-meta.json"

files_count=$(grep -o '"files":\[[^]]*\]' "$TMP/repo1/.code-review/.pr-1-meta.json" | grep -c '"name"' || true)
if [[ "$files_count" -ne 0 ]]; then
  echo "FAIL: test 3 expected 0 files for empty PR"
  exit 1
fi
echo "OK: empty-PR detection works"

# --- Test 4: env var override is read ---

REVIEW_PR_MAX_DIFF_LINES=500 bash -c '
  threshold=${REVIEW_PR_MAX_DIFF_LINES:-2000}
  if [[ "$threshold" != "500" ]]; then
    echo "FAIL: test 4 env override not honored"
    exit 1
  fi
  echo "OK: REVIEW_PR_MAX_DIFF_LINES override works"
'

echo ""
echo "All review glue tests passed."
```

Make it executable:

```bash
chmod +x skills/review-pr/tests/test_review.sh
```

- [ ] **Step 2: Run it**

Run: `bash skills/review-pr/tests/test_review.sh`
Expected: four `OK:` lines and `All review glue tests passed.`

- [ ] **Step 3: Commit**

```bash
cd <repo-root>/agent-skills-setup
git add skills/review-pr/tests/test_review.sh
git commit -m "test(review-pr): review bash glue tests"
```

---

## Task 6: Write user-facing READMEs

**Files:**
- Create: `skills/mine-review-patterns/README.md`
- Create: `skills/review-pr/README.md`

- [ ] **Step 1: Write the mining README**

Create `skills/mine-review-patterns/README.md`:

```markdown
# mine-review-patterns

Scan a repo's closed PRs to produce `.code-review/playbook.md`, a curated
checklist future reviewers consult.

## Install

```bash
bash scripts/install.sh
```

This is a `local` skill in `registry.txt`; it's installed automatically
along with the others.

## Usage

```bash
cd /path/to/your/repo
/mine-review-patterns          # default 50 PRs
/mine-review-patterns 100      # scan 100 PRs
```

The skill writes `.code-review/playbook.md` and prints a summary.
**It does not auto-commit.** Read the playbook, edit if needed, then
commit when ready.

First run will take ~15 minutes for 50 PRs (rate-limited by `gh`).

## Output

`.code-review/playbook.md` — markdown with four sections:
1. Recurring issues caught in review
2. Patterns reviewers missed (caught later via hotfix/revert)
3. Reviewer over-focus (categories that did not prevent real bugs)
4. Domain gotchas (repo-specific rules not obvious from code)

## Re-mining

Re-run quarterly or when major architectural changes land. Each run
overwrites `.code-review/playbook.md` — rely on git history to compare.

## Troubleshooting

- `gh auth status` fails: run `gh auth login`.
- Rate-limited mid-run: re-run; the skill resumes from
  `.code-review/.mining-state.json`.
- Wrong repo detected: `cd` into the target repo before invoking.
```

- [ ] **Step 2: Write the review README**

Create `skills/review-pr/README.md`:

```markdown
# review-pr

Review a single PR using the mined playbook. Produces a full local report
plus a 3-5 issue comment draft (not auto-posted).

## Install

```bash
bash scripts/install.sh
```

Installed automatically as a `local` skill.

## Prerequisite

`.code-review/playbook.md` must exist. Run `/mine-review-patterns` first.

## Usage

```bash
cd /path/to/your/repo
/review-pr 573
```

The skill writes:
- `.code-review/reviews/PR-573.md` — full report (all findings + reasoning)
- `.code-review/reviews/PR-573-comment.md` — short comment draft

Then prints the comment draft and the exact `gh pr comment` command to
post it. **You decide whether to post.**

## Configuration

| Var | Default | Effect |
|---|---|---|
| `REVIEW_PR_MAX_DIFF_LINES` | `2000` | Large-PR warning threshold |
| `REVIEW_PR_MODEL` | `claude-sonnet-4-6` | Review model |

## Output format

The comment draft is at most 5 issues, ranked by severity:

```markdown
## Review summary

3 issues worth flagging. Full details: `.code-review/reviews/PR-573.md`

**Critical:**
- `auth/middleware.go:47` — missing tenant_id check.

**Important:**
- `services/billing.go:128` — error from chargeCard swallowed.

**Minor:**
- `db/migrations/0042.sql` — no down migration.
```

If no critical or important issues, the draft is one line: `No critical
or important issues. N minor notes in the full report.`

## Troubleshooting

- "Playbook not found": run `/mine-review-patterns` first.
- Large PR: the skill prompts for confirmation. Reviews of 2000+ line
  PRs tend to be noisy — consider splitting the PR.
- Wrong report: the model occasionally over-flags. Edit the comment
  draft before posting; the full report keeps everything for context.
```

- [ ] **Step 3: Commit**

```bash
cd <repo-root>/agent-skills-setup
git add skills/mine-review-patterns/README.md skills/review-pr/README.md
git commit -m "docs(review-pr): user-facing READMEs"
```

---

## Task 7: Install and end-to-end smoke test

**Files:** none modified — verification only.

- [ ] **Step 1: Install**

```bash
cd <repo-root>/agent-skills-setup
bash scripts/install.sh
```

Expected: install proceeds without error, both new skills are mentioned in the output.

- [ ] **Step 2: Verify symlinks**

```bash
ls -la ~/.claude/skills/mine-review-patterns ~/.claude/skills/review-pr
```

Expected: both are symlinks to `<repo-root>/agent-skills-setup/skills/...`.

- [ ] **Step 3: Run all bash glue tests**

```bash
cd <repo-root>/agent-skills-setup
bash skills/mine-review-patterns/tests/test_mining.sh
bash skills/review-pr/tests/test_review.sh
```

Expected: both end with `All ... glue tests passed.`

- [ ] **Step 4: Smoke test mining**

In a fresh terminal:

```bash
cd /path/to/your/repo
```

Then in Claude Code: `/mine-review-patterns 5`

This runs against 5 PRs only (small batch, ~2 minutes). Confirm:
- A `.code-review/playbook.md` is written
- Output mentions PR numbers
- Skill does NOT commit anything
- The command prints the "Review and edit, then commit when ready" message

If it fails, investigate. Do not declare done.

- [ ] **Step 5: Smoke test review**

After the mining smoke test produced a playbook:

```bash
/review-pr <some-recent-closed-pr-number>
```

Pick a small-ish closed PR (under 500 lines changed). Confirm:
- `.code-review/reviews/PR-<n>.md` is written
- `.code-review/reviews/PR-<n>-comment.md` is written
- The comment draft is printed inline
- The skill does NOT auto-post to the PR
- The `gh pr comment` command shown is correct

- [ ] **Step 6: No commit — smoke test only**

If both smoke tests passed, the skill is ready. If either failed, return to the responsible task and fix.

---

## Done criteria

- [ ] Both `mine-review-patterns` and `review-pr` skills exist with non-placeholder SKILL.md and prompt assets.
- [ ] `registry.txt` registers both as `local`.
- [ ] Bash glue tests pass for both skills.
- [ ] `bash scripts/install.sh` symlinks both into `~/.claude/skills/`.
- [ ] Manual smoke tests against the target repo produce a playbook and a review without auto-posting.
- [ ] Both READMEs document install, usage, and troubleshooting.
