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
