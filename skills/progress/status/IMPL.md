---
subcommand: status
group: progress
slash: /progress-status <STORY-ID>
output: stdout only
---

# progress/status — Gate Status Checklist

## What this does

Derives which spec-gated workflow gates a story has passed by checking for
the artifact files each gate is documented to produce (see each group's
`SKILL.md` "Output" column). Prints a checklist plus a suggested next
command. Read-only — writes nothing.

## Steps

1. Resolve the story folder:
   ```bash
   source ~/.agent-skills-setup/lib.sh
   STORY_DIR=$(resolve_story_dir "$1") || exit 1
   ```
   If this fails, the story hasn't been through `/intake-jira-story` yet.
   Report that and stop — there's nothing to check.

2. Check each gate in order. For each, note found/missing:

   | Gate | Check | Detection |
   |---|---|---|
   | intake | `story.md` | file exists |
   | intake | `intake-summary.md` | file exists |
   | audit | `audit-report.md` | file exists |
   | audit | `domain-risk.md` | file exists |
   | audit-handoff | — | inferred: openspec proposal exists (see below) |
   | external (conditional) | `external-deps.md` | file exists — **skip this row entirely if absent**, it's conditional, not a required gate |
   | openspec | `./openspec/changes/<change-id>/proposal.md` | read `openspec_changes` from `intake-summary.md` frontmatter, check each |
   | apidog | `apidog/contract.md`, `apidog/mocks.md`, `apidog/testcases.md` | file exists (report each independently — they don't have to all be done at once) |
   | testing-plan | `test-plan.md` | file exists |
   | jira-subtasks | `pr-plan.md` with sub-task IDs written back | file exists AND contains at least one ticket ID pattern |
   | testing-write | RED test stubs + `U<n>` tickets | inferred from `pr-plan.md` entries having both a ticket ID and a PR link |
   | review-guardrails | — | inferred: PR referenced in `pr-plan.md` exists and is not still in initial commit state (best-effort, don't over-claim) |
   | release-readiness | `release/readiness.md` | file exists |

3. Print a checklist, ordered top to bottom as the workflow runs, using `[x]`
   for found, `[ ]` for missing, and skip the `external` row if
   `external-deps.md` doesn't exist (don't print `[ ]` for a gate that may
   not even apply to this story).

4. After the checklist, print exactly one suggested next command — the
   first missing required gate, in workflow order. If everything through
   `release-readiness` is present, print `All known gates present.` instead
   of a next-command suggestion.

5. For any gate marked via inference rather than a direct file check, label
   it `(inferred)` in the output so the user knows it's not a hard fact.

## Output format

```
Story: VOR-31324
./docs/stories/VOR-31324-vortex-permission-migration/

[x] intake         story.md, intake-summary.md
[x] audit          audit-report.md, domain-risk.md
[x] openspec       vor-31324-vortex-permission-migration/proposal.md (approved)
[ ] apidog         no contract.md yet
[ ] testing-plan
[ ] jira-subtasks
[ ] release

Next: /apidog-contract VOR-31324
```

If a story has no `openspec_changes` in its `intake-summary.md` frontmatter
yet, print `openspec` as missing and stop the checklist there — nothing
downstream can be verified without a change-id to look inside.

## Do not

- Do not write any file. This subcommand is stdout-only, always.
- Do not guess that a gate ran just because enough time has passed — only
  file existence and the explicit inference rules above count as evidence.
- Do not treat a missing `external-deps.md` as a failure — most stories
  don't have an external dependency at all.
