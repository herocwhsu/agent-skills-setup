---
subcommand: archive-check
group: release
slash: /release-archive-check <STORY-ID>
output: ./docs/stories/<JIRA-ID>-<slug>/archive.md
---

# release/archive-check — Final Archive Checker

Verifies the complete spec archive for a story before considering it closed.
Walks every OpenSpec change-id linked to the story and confirms each is
archived. Also checks that the story folder has all required evidence.

Corresponds to workflow spec §14.11, skill 38 (openspec-archive-checker).

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
STORY_DIR=$(resolve_story_dir "$1") || exit 1
```

`intake-summary.md` must exist with an `openspec_changes` frontmatter list.
If missing, the check can still run but will warn about the missing link.

## Step 1 — Read the OpenSpec change-id list

```bash
# Extract openspec_changes from intake-summary.md frontmatter
CHANGE_IDS=$(python3 -c "
import sys
import re
content = open('$STORY_DIR/intake-summary.md').read()
# Extract YAML frontmatter between --- markers
m = re.search(r'^---\n(.+?)\n---', content, re.DOTALL)
if not m:
    sys.exit(0)
fm = m.group(1)
in_changes = False
for line in fm.splitlines():
    if line.strip() == 'openspec_changes:':
        in_changes = True
    elif in_changes and line.strip().startswith('- '):
        print(line.strip()[2:])
    elif in_changes and not line.strip().startswith('-'):
        in_changes = False
" 2>/dev/null)
```

## Step 2 — For each change-id, check OpenSpec archive

```bash
for CHANGE_ID in $CHANGE_IDS; do
  ARCHIVE_PATTERN="./openspec/changes/archive/*-${CHANGE_ID}"
  if ls $ARCHIVE_PATTERN 2>/dev/null | grep -q .; then
    echo "  ✓ $CHANGE_ID — archived"
  else
    echo "  ✗ $CHANGE_ID — NOT archived (run /opsx:archive in the repo)"
  fi
done
```

## Step 3 — Check story folder evidence

Required files per workflow spec §13:

| File | Required | Check |
|---|---|---|
| `story.md` | Yes | exists |
| `audit-report.md` | Yes | exists + `status: pass` |
| `apidog/contract.md` | Yes for API features | exists |
| `test-plan.md` | Yes | exists |
| `release/readiness.md` | Yes | exists + `status: ready` |
| `intake-summary.md` | Yes | exists + `openspec_changes` list non-empty |

Optional but checked:
- `domain-risk.md`
- `repo-context.md`
- `amendments/` — logged if any exist
- `change-requests/` — logged if any exist

## Step 4 — Check lifecycle state in OpenSpec proposal

For each change-id, read:
```
./openspec/changes/<change-id>/proposal.md
```

Check frontmatter `status:` field. For archive, it must be `released` or
already show as archived by file location. If `status: implementing` or
`status: approved`, the change was never released — flag it.

## Output format

Write to `$STORY_DIR/archive.md`:

```markdown
---
story: <JIRA-ID>
checked_at: <YYYY-MM-DD>
status: complete | incomplete
blocking_count: <n>
---

# Archive Check: <JIRA-ID>

## OpenSpec Changes

| Change ID | Archived? | OpenSpec status | Notes |
|---|---|---|---|
| example-100-add-camera-group-filter | ✓ | released | Archived 2026-06-10 |
| example-100-cr-group-permission | ✗ | implementing | Not archived — run /opsx:archive |

## Story Folder Evidence

| File | Status | Notes |
|---|---|---|
| story.md | ✓ | |
| audit-report.md | ✓ | status: pass |
| apidog/contract.md | ✓ | |
| test-plan.md | ✓ | |
| release/readiness.md | ✓ | status: ready |
| intake-summary.md | ✓ | 2 openspec_changes linked |

## Amendments
<n> amendment(s) on file: amendments/2026-05-20-clarify-cursor.md

## Change Requests
<n> change request(s) on file: change-requests/2026-05-25-add-site-filter.md

## Blocking Items
- example-100-cr-group-permission not archived — run `/opsx:archive` in repo

## Verdict
<ARCHIVE COMPLETE | INCOMPLETE — N items remain>
```

Set `status: complete` only when all change-ids are archived and all
required evidence files exist. `status: incomplete` otherwise.

## Common mistakes

| Mistake | Fix |
|---|---|
| Running archive-check before /release-readiness passes | Run readiness first — archive-check assumes the feature is released |
| Missing intake-summary.md | Run /intake-spec-summary (Phase 2 full) or create it manually with openspec_changes list |
| Forgetting to /opsx:archive in the repo | The story-level archive.md is only complete after each OpenSpec change-id is archived via `/opsx:archive` |
