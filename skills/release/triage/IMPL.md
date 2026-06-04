---
subcommand: triage
group: release
slash: /release-triage <STORY-ID> "<issue description>"
output: ./docs/stories/<JIRA-ID>-<slug>/release/triage.md
---

# release/triage — Post-Release Issue Triage

Classifies a post-release issue and recommends the correct next step.
Never push a post-release issue directly back into the original story
without triaging first.

Merged: post-release-triage + follow-up-proposal-generator (they always
co-trigger — after classifying, the right next step is immediately clear).

Corresponds to workflow spec §14.11, skills 35 and 37.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
STORY_DIR=$(resolve_story_dir "$1") || exit 1
ISSUE_DESCRIPTION="$2"
```

Read `$STORY_DIR/release/readiness.md` and the relevant OpenSpec proposal to
understand what was actually approved.

## Classification logic

Work through these questions in order:

1. Is this causing system downtime, data corruption, security risk, or
   severe customer impact right now?
   → **Incident** — trigger incident process + hotfix. Do not use this skill.

2. Does the actual behavior differ from what the approved OpenSpec proposal says?
   → **Bug** — use `/release-bugfix-spec`

3. Was behavior that previously worked now broken?
   → **Regression** — use `/release-bugfix-spec` + `/testing-regression`

4. Does the approved spec not clearly cover this scenario?
   → **Spec gap** — create a clarification + new OpenSpec proposal if needed

5. Is this new functionality or an improvement beyond the original spec?
   → **Enhancement** — new OpenSpec proposal via `/opsx:propose`

6. Is this a deployment, monitoring, configuration, or data issue?
   → **Operational** — ops/infra ticket

## Output format

Write to `$STORY_DIR/release/triage.md`:

```markdown
---
story: <JIRA-ID>
issue: <one-line description>
triaged_at: <YYYY-MM-DD>
classification: incident | bug | regression | spec-gap | enhancement | operational
---

# Post-Release Triage: <JIRA-ID>

## Issue
<full description>

## Classification
**<TYPE>** — <one sentence rationale>

## Evidence
- Original spec behavior: <what the approved OpenSpec says>
- Actual behavior: <what is happening>
- Diff: <what is different>

## Recommended Next Steps

### If Bug or Regression
```
/release-bugfix-spec <STORY-ID> <BUG-JIRA-ID>
/testing-regression <STORY-ID>
```
*Rule: no regression test, no bugfix closure.*

### If Spec Gap
Create a clarification OpenSpec amendment or follow-up story:
```
/review-amend <STORY-ID> <slug>     # if small clarification
/opsx:propose <new-change-id>       # if new scope needed
```

### If Enhancement
```
/intake-jira-story <NEW-STORY-ID>
... run full spec-gated workflow for the new story
```

### If Operational
Create an ops/infra ticket. No spec change needed.

## Do NOT
- Reopen the original story to absorb new scope
- Fix a bug without a regression test
- Treat a spec gap as a bug (they need different processes)
```
