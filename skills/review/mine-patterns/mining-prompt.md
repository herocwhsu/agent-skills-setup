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
