---
subcommand: context-scan
group: repo
slash: /repo-context-scan <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/repo-context.md
---

# repo/context-scan — GitHub Repo Context Scan

Scans the target repo to understand the implementation surface before an
OpenSpec proposal is written. Without repo context, the proposal may describe
things that don't match how the codebase actually works.

Corresponds to workflow spec §14.3, skills 7–9 (merged into one scan).

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

Requires `gh` CLI authenticated (`gh auth status` passes) and the current
working directory is inside a clone of the target repo.

## Step 1 — Identify affected areas from intake

Read `$STORY_DIR/story.md` and `$STORY_DIR/audit-report.md` (if exists).
Extract key domain terms: entity names, API paths, feature keywords.

## Step 2 — Scan repo

Run the following in the target repo root:

```bash
# Related API handlers
grep -r --include="*.go" --include="*.ts" --include="*.py" -l "<keyword>" . 2>/dev/null | head -20

# Existing test files for affected area
find . -type f \( -name "*_test.go" -o -name "*.test.ts" -o -name "*.spec.ts" \) \
  | xargs grep -l "<keyword>" 2>/dev/null | head -10

# Database migration patterns
find . -type f -name "*.sql" -o -name "*migration*" | head -10

# Permission middleware
grep -r --include="*.go" --include="*.ts" -l "permission\|authorize\|middleware" . 2>/dev/null | head -10
```

Use `gh` to scan recent PRs for context on the relevant area:

```bash
gh pr list --state merged --limit 20 --json title,url,mergedAt \
  --jq '.[] | "\(.mergedAt) \(.title) \(.url)"' 2>/dev/null | grep -i "<keyword>" | head -5
```

## Step 3 — Map the implementation surface

Identify:

| Surface | What to find | Where to look |
|---|---|---|
| Affected modules | Which packages/dirs contain the relevant code | `grep` results |
| Related APIs | Existing endpoints that will change or be called | Handler files |
| Related DTOs / structs | Request/response types already defined | Model files |
| DB schema | Existing tables and columns that will be affected | Migration files |
| Test patterns | How existing tests are structured | Test files |
| Coding conventions | Naming patterns, error handling style | Adjacent source |
| Known limitations | TODOs, FIXMEs, comments warning about edge cases | `grep -r FIXME\|TODO` |

## Output format

Write to `$STORY_DIR/repo-context.md`:

```markdown
---
story: <JIRA-ID>
scanned_at: <YYYY-MM-DD>
repo: <repo name from git remote>
---

# Repo Context: <JIRA-ID>

## Affected Modules
- `<path>` — <why affected>

## Related APIs
| Method | Path | File | Notes |
|---|---|---|---|

## Related DTOs / Structs
- `<TypeName>` in `<file>` — <relevant fields>

## Database Tables
- `<table_name>` — <relevant columns>

## Existing Test Coverage
| Area | Test file | Coverage notes |
|---|---|---|

## Coding Conventions Observed
- Error handling: <pattern>
- Naming: <pattern>
- Auth/permission: <pattern>

## Known Limitations / TODOs
- `<file:line>` — <TODO text>

## Recommended Reading Before Writing OpenSpec
- `<file>` — <why>
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Scanning the wrong repo | Confirm `git remote -v` matches the story's product area |
| Missing the permission layer | Always grep for middleware/authorize — it's easy to miss and always relevant |
| Copying raw `grep` output | Summarize and interpret — the agent writing the OpenSpec needs context, not a file dump |
