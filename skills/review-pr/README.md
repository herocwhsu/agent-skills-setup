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
