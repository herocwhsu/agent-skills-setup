---
subcommand: lint
group: sre-migration
slash: /sre-migration-lint <STORY-ID>
output: stdout report
---

# sre-migration/lint — Gate the draft before it is filed

Runs 12 checks against a drafted ticket and its samples, then reports the
high-risk criteria's inputs for a human to judge.

## Overview

Every check below traces to a real rejection or a template rule. None is
invented hygiene — that provenance is the first thing to preserve if this list
is ever cut down.

Three filed tickets supply the ground truth:

- one was bounced because the referenced commit was not yet on `main`, and
  because it declared an operation not-provided while attaching that same
  operation's dev output;
- one was filed with every 說明 empty and no commands at all;
- one named one company id in its description while the SQL in its comments
  targeted a different one, with units drifting between 年 and pcs.

## The 12 checks

| id | Check | Fails when |
|---|---|---|
| `sha-on-main` | The referenced commit is on `main` | `git merge-base --is-ancestor <sha> origin/main` is false |
| `not-provided-contradiction` | No operation declares `是否提供: No` while its output is attached | Both appear for the same operation |
| `empty-operation` | Every provided operation has a non-empty 說明 and a command block | Either is missing |
| `idempotency-answered` | Every operation answers 可否重複執行 | Any is blank |
| `company-id-guard` | Every `company_id` in the body matches a sample's `expected_*` | Body and samples disagree |
| `unit-drift` | Quantity units are consistent | The same quantity appears as both 年 and pcs |
| `env-samples-complete` | A sample exists for each **deployed** env (dev/stage/prod) | An env has no sample and `NOTES.md` does not explain the absence |
| `no-prod-in-lower-env` | No prod identifier appears in a lower-environment sample | A prod id or ship-to code leaks downward |
| `six-operations` | All six operations are addressed | One is absent with no 是否提供: No + reason |
| `pii-answered` | PII is Yes/No/不確定 with data types named | Unanswered, or answered with no types |
| `notes-present` | `NOTES.md` names every **prod** items file | `NOTES.md` is absent, or a prod file is never named |
| `high-risk-inputs` | The five criteria's inputs are all reported | Any input is unavailable |

## Which checks are executable

Ten of the twelve run as code today. **Do not present the other two as having
run** — an agent performs those, and saying otherwise makes this gate a claim
rather than a check.

| Runs via `lib/lint.sh` | Performed by the agent |
|---|---|
| `not-provided-contradiction` | `no-prod-in-lower-env` (needs cross-env comparison) |
| `empty-operation` | `high-risk-inputs` (needs precheck output) |
| `idempotency-answered` | |
| `unit-drift` | |
| `pii-answered` | |
| `six-operations` | |
| `sha-on-main` (needs `SRE_MIGRATION_REPO`) | |
| `company-id-guard` (needs `SRE_MIGRATION_ITEMS_DIR`) | |
| `notes-present` (needs `SRE_MIGRATION_ITEMS_DIR`) | |
| `env-samples-complete` (needs `SRE_MIGRATION_ITEMS_DIR`) | |

Six operate on the ticket body alone. `sha-on-main` needs the work repo, and
`company-id-guard`, `notes-present` and `env-samples-complete` need the tool's
`templates/<jira-id>/` directory; all four refuse with exit 2 rather than
skipping when their env var is unset, because an unrun check must never read as
clean. `company-id-guard`
also reports **N/A** when a directory holds no items-file arrays — a tool whose
input is one JSON object per file has no `company_id` semantics, and flagging it
would fire on shipped files that are correct as written.

The two remaining agent-performed checks are candidates for promotion once their
fixtures grow trees — `no-prod-in-lower-env` needs samples from two environments
whose identities are known to differ, `high-risk-inputs` needs real precheck
output.

```bash
# One check per invocation; exit 0 clean, 1 flagged, 2 usage error.
bash lint/lib/lint.sh --check empty-operation "$STORY_DIR/migration-ticket.md"

# The six body-only checks, collecting failures rather than stopping at the first:
for c in not-provided-contradiction empty-operation idempotency-answered \
         unit-drift pii-answered six-operations; do
  bash lint/lib/lint.sh --check "$c" "$STORY_DIR/migration-ticket.md" || rc=1
done

# The four needing external state:
SRE_MIGRATION_REPO=/path/to/work-repo \
  bash lint/lib/lint.sh --check sha-on-main "$STORY_DIR/migration-ticket.md"
for c in company-id-guard notes-present env-samples-complete; do
  SRE_MIGRATION_ITEMS_DIR=extend/scripts/<tool>/templates/<jira-id> \
    bash lint/lib/lint.sh --check "$c" "$STORY_DIR/migration-ticket.md" || rc=1
done
```

### Three outcomes, not two

`company-id-guard` distinguishes them deliberately, because collapsing any of
them into a plain pass hides something:

| Outcome | Meaning |
|---|---|
| `FAIL` | A real target has no guard and nothing explains why |
| `EXEMPT` | A null guard that the ticket's `NOTES.md` justifies, quoted back |
| `N/A` | The directory has no items-file arrays at all (different tool shape) |
| `OK` | Checked, every target guarded |

The `EXEMPT` path exists because a null guard is sometimes correct. One shipped
file carries nulls on purpose: `company_id` there is a disposable stage test
account, and an earlier version filling in the real customer's guard values made
the tool abort. Flagging that is a false positive; passing it silently would
hide a genuinely unguarded target.

To earn an exemption, the `NOTES.md` section naming the file must speak to
**both** the guard fields and their being null. Merely naming the file is not
enough — otherwise the exemption degrades into "has a `NOTES.md`", which a
mutation test asserts against. This is a low bar an author can satisfy
deliberately, and that is the point: it converts a silent null into an explicit,
reviewable statement. It does not verify the statement is true.

## Steps

### Step 1 — Locate the draft and its samples

```bash
STORY_ID="$1"
STORY_DIR=$(find ./docs/stories -maxdepth 1 -type d -name "${STORY_ID}-*" | head -1)
[[ -n "$STORY_DIR" ]] || { echo "ERROR: no story folder for $STORY_ID" >&2; exit 1; }
TICKET="$STORY_DIR/migration-ticket.md"
FLOW="$STORY_DIR/command-flow.md"
```

### Step 2 — Read the required sections from the template, not from here

The template artifact is the source of which sections and per-operation
sub-fields must exist. Reading it rather than hardcoding a list means a renamed
section fails loudly instead of being silently skipped.

### Step 3 — Environment coverage is the deployed trio, not the `--site` list

```bash
SRE_MIGRATION_ITEMS_DIR=extend/scripts/<tool>/templates/<jira-id> \
  bash lint/lib/lint.sh --check env-samples-complete "$STORY_DIR/migration-ticket.md"
```

Do **not** derive the required set from the tool's `--site` flag — see
"Why environment coverage is the deployed trio" below; that rule flags two of the
four shipped ticket directories.

### Step 4 — Run the checks and report

One line per check: the id, PASS or FAIL, and on failure the offending item by
name. Naming the item is what makes the report actionable, and a check that
names a sibling item that is legitimately fine is a false positive worth
fixing.

Exit non-zero when any check fails, so this can gate.

### Step 5 — Report high-risk inputs, never a verdict

```
High-risk inputs (a human decides):
  affected rows      : <n>   vs thresholds 10,000 and 30% of table
  PII category       : <category or 不確定>
  estimated downtime : <duration>  vs threshold 5 min
  services / DBs     : <count>
  rollback provided  : <yes/no>
```

Print the inputs and stop. Do **not** conclude "this is high risk" and do not
fill the sign-off field — the consequence of that call is a management approval
and a low-traffic execution window, which is a human's to make.

## Why environment coverage is the deployed trio, not the `--site` list

Deriving the required set from the tool's own `--site` flag sounds right and
flags two of the four shipped ticket directories:

| Tool | `--site` accepts | A shipped dir has | Verdict under that rule |
|---|---|---|---|
| the RDS correction tool | dev, stage, prod | prod, stage | missing **dev** |
| the API reclaim tool | local, dev, stage, prod | dev, stage, prod | missing **local** |

Both are legitimate. `NOTES.md` in the first records that dev holds no data for
that customer at all (`WHERE customer_no='…'` returns nothing there), so
mechanism testing used ad-hoc files against a disposable account instead. And
`--site local` resolves to `http://localhost:8080` — a developer's own machine,
which needs no checked-in target file.

So the rule is: **dev, stage, prod**, with `NOTES.md` able to exempt a specific
one. `local` is never required.

Mentioning an environment is not explaining its absence. Every `NOTES.md` quotes
the `--site <dev|stage|prod>` usage, so a bare mention would exempt everything;
the exemption requires an absence statement in the same sentence as the env name.
A mutation test proves this: stripping only the dev-absence sentences from the
real `NOTES.md`, while leaving three lines that still say "dev", correctly fails.

One earlier measurement of mine was wrong and is worth recording: a count of
"five distinct env prefixes" included `test`, but `test-correction-dev.json`
tokenizes to *both* `test` and `dev` — `test-correction` is a filename
descriptor, not an environment. There are four `--site` values, three deployed.

## Why `notes-present` checks only prod files

`NOTES.md` exists in 4/4 real ticket directories, but only one documents with
per-file `` ## `name.json` `` sections — the rest do it thematically
(`## Input files`, `## Why the prod file has no expected_name`). One real
directory has four items files named nowhere in its notes, and they are correct
as written. Requiring every file documented would flag that shipped work.

Every **prod** file, however, is named in all four directories. That is the rule
worth enforcing: prod is where an unrecorded target actually costs something,
since company ids are per-environment auto-increment and the notes are the only
record of why a given id is the right one. A directory with no prod file reports
N/A rather than passing.

A missing `NOTES.md` does **not** weaken `company-id-guard` — it makes it
stricter, because an undocumented null guard can no longer earn an `EXEMPT`. The
two checks are independent.

## Common Mistakes

| Mistake | Why it matters |
|---|---|
| Hardcoding the template's section list | A renamed section then passes silently |
| Deriving the required envs from `--site` | Flags 2 of 4 shipped ticket dirs |
| Concluding high risk | Not the skill's call; it triggers a management step |
| Reporting a failure without naming the item | The report is not actionable |
| Flagging a sibling that is legitimately fine | False positives get a gate ignored |
| Exiting 0 on failure | It stops being a gate |
