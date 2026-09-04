---
title: sre-migration skill — SOC2 migration-ticket scaffold, draft, lint, ticket
date: 2026-09-01
status: draft
---

# sre-migration skill

A top-level skill `skills/sre-migration/` that produces the artifacts a
`Change Request - Migration Execution` ticket needs: the per-environment
correction tool inputs, the ticket body, the per-environment command flow, and
the Jira issue itself — with a lint gate between drafting and filing.

Supersedes the 2026-08-21 sketch, which was reverse-engineered from two shipped
tools before the canonical template had been read. Four of its premises were
wrong; see Key Decisions.

## Problem

Every SOC2 migration request is currently hand-written, and three of the four
filed so far were rejected or incomplete for mechanical reasons:

- **VSRV-2487** — the ticket declared `precheck: No` while attaching dev
  precheck output, and the referenced commit was not yet on `main`. Both are
  checkable before filing.
- **VSRV-2527** — filed with every `各操作說明` 說明 empty and no commands at
  all. The execution steps had to be written by hand afterwards, outside the
  ticket, and were discarded once the tooling itself landed on `main`.
- **VSRV-1665** — the description named one company id and region code while
  the SQL in the comments targeted a different `company_id` entirely, and units
  drifted between `回收 13 年` and `回收 13 pcs`. (Its actual blocker is a
  business decision, not paperwork — out of scope here.)

Nothing in the repo encodes the template's requirements, so each ticket
re-derives them from the previous ticket, and drift compounds.

## Goals

- Scaffold a correction tool that conforms to the template's operation set,
  with one input sample per environment the tool accepts.
- Draft the ticket body and the per-environment command flow from a story.
- Lint a draft against the failure modes above before it is filed.
- File the issue in Jira with the correct fields.
- Read the template at runtime rather than freezing its section list in the
  skill.

## Non-Goals

- **Docker packaging — deferred.** The template mandates a Dockerfile at the
  `Path` root, tagged with the Jira number, with all six operations behind one
  entrypoint (`docker run <img> precheck --target=dev`). Neither shipped tool
  has a Dockerfile. Pending a separate decision; the rules are recorded here so
  it can be picked up without re-reading the page. Note the template's code
  macros did not survive text extraction, so the exact Dockerfile body still
  needs re-fetching when this is taken up.
- **Deciding whether a change is high-risk.** `/sre-migration-lint` reports the
  five criteria's inputs; a human decides. The skill never prints a verdict and
  never fills the sign-off field.
- **Retrofitting `restore` into the shipped tools** (three as of `a4cd5da4`).
  They are merged and reviewed; changing them is its own change. The scaffold
  emits `restore` for new tools and lint flags its absence as a declaration to
  justify, not a bug.
- Replacing `utils/confluence-tree`, which keeps `CONFLUENCE_HOST` for
  genuinely self-hosted pages.

## Template facts (verified 2026-09-01)

The guide page — "VORTEX Migration Ticket 申請指南" — read via
`https://$JIRA_HOST/wiki/rest/api/content/<page-id>?expand=body.storage` and
`/wiki/api/v2/pages/<page-id>?body-format=storage`, both HTTP 200. The page id
is taken from the link in the story, not stored here.

**Six operations** — more than any shipped tool implements. The RDS correction
tool has five `cmd_*` and no `restore`; the other two are flag-driven
(`--apply` / `--rollback`) with no named operation set at all. The gap is
widest, not narrowest, for the newest tool:

| Operation | Purpose |
|---|---|
| `precheck` | Verify preconditions, output affected row count |
| `backup` | Snapshot before the change, as rollback/restore's data source |
| `migrate` | The change itself |
| `verify` | PASS/FAIL on the result |
| `rollback` | Logical inverse (e.g. UPDATE back to the old value) |
| `restore` | Whole-restore from the backup — **distinct from rollback** |

Each operation declares three sub-fields: `是否提供` (Yes/No, with a reason
when No), `說明`, and `可否重複執行` (idempotency).

**Description blocks**: `變更說明`, `程式碼位置` (Repo / Branch or Tag /
Commit SHA / Path), `目標資源/資料表`, `是否提供 Rollback`,
`涉及 PII/機敏資料`, `執行時機`, `各操作說明`, `precheck 輸出 (Dev)`,
`所需權限申請`.

**Five high-risk criteria**, any one forcing 處級主管 sign-off and a
low-traffic window: no rollback; affected rows ≥ 10,000 **or** ≥ 30% of the
table (whichever is lower); PII / financial / auth / encryption-key data;
estimated downtime > 5 min; multiple services or multiple prod databases.

**PII** is enumerated in five categories, and `不確定` is an allowed answer
deliberately deferred to SRE at pre-check.

Also: a six-item pre-application checklist, and a prohibition on using prod
data as dev/stage verification data.

## Template source

**Read the story folder first; fetch only as a fallback.** As of `a4cd5da4`
(2026-09-03) the guide is a checked-in artifact:
`docs/stories/<STORY>/confluence-vortex-migration-ticket-guide.md`, 381 lines,
carrying its own `Source:` URL on line 3. That follows the established intake
convention — two older story folders carry `confluence-526576521.md` the same
way — so `draft` resolving it from the story folder costs no network, no
credential, and no duplication of what `/intake-web-page` already did.

Resolution order:

1. A `confluence-*migration-ticket*.md` in the story folder → use it, and
   report which file and which `Source:` line it came from.
2. Absent → fetch, then **write it into the story folder** so the next
   subcommand and the next story reuse it rather than re-fetching.

The fallback fetch still needs the host right, and `CONFLUENCE_HOST` is the
wrong source for this page: on Atlassian Cloud, Confluence is served from the
Jira site host under `/wiki` and answers to the **Jira** credential, while the
self-hosted `$CONFLUENCE_HOST` resolves only on the corporate network and
serves self-hosted pages, not Cloud page ids. So take the host from the page URL
in the story; when it equals `$JIRA_HOST`, authenticate with the Jira keychain
entry and call `/wiki/...` on it; otherwise fall back to `CONFLUENCE_HOST` and
its own credential. **No new config key** — the host is already in `$JIRA_HOST`
and in the URL, and a third copy could drift out of sync with both.

Credentials follow the existing pattern: `load_config` → `service_slug` →
`require_secret`, secret unset immediately, never printed.

## Per-environment samples

The shipped tools ship one input file per environment, and the diffs show only
target identity varies — `company_id`, `expected_name`, `expected_ship_to_code`
— with structure identical. This becomes a first-class output rather than the
single generic template the earlier sketch produced.

**Coverage is the deployed trio — dev, stage, prod — not the tool's whole
`--site` list.** Deriving it from `--site` was the original design here, and
measurement disproved it: that rule flags two of the four shipped ticket
directories. One tool accepts `local` and ships no local sample, because
`--site local` is `http://localhost:8080`, a developer's own machine; and one
directory has no dev sample because dev holds no data for that customer to
resolve against. So `lint` requires dev/stage/prod, lets `NOTES.md` exempt a
specific env with an absence statement, and reports N/A for a tool taking **no
items file at all** (see `update-cognito-unverified`, below).

`expected_name` / `expected_ship_to_code` are the guard against VSRV-1665's
target mismatch: they make the tool refuse a `company_id` that does not
resolve to the named company.

Each environment has its own disjoint company id and ship-to code — a debug
dealer in dev, a tester account in stage, the real customer in prod. Because
they are disjoint, the template's prod-data prohibition is mechanizable: no
identifier belonging to prod may appear in a lower-environment sample. The concrete
values stay in the work repo's `templates/<jira-id>/` files and the story
folder; this spec deliberately does not copy them.

**Schema**: the samples are JSON, so the scaffold emits
`scaffold/templates/items-file.schema.json` alongside them, and
`tests/test_sre_migration.sh` validates every generated and checked-in sample
against it. The schema must mark the guard fields (`expected_name` /
`expected_ship_to_code`) required — a sample that omits them silently disables
the `company-id-guard` protection. A schema that nothing runs is worse than no
schema, because it reads as a guarantee.

**Naming**: two conventions exist —
`<tool>/templates/<jira-id>/test-correction-{dev,stage}.json` but
`<target>-correction-prod.json` in one tool, versus
`<tool>/templates/<jira-id>/<env>-<target>-<action>.json` in the other. Per
Rule 7 the scaffold emits the **env-prefix** form only, and the mixed form is
flagged for deprecation rather than supported alongside it. VOR-33290 settled
this in practice: its 11 new samples all use the env-prefix form, so the
convention picked here is the one the repo converged on independently.

**`NOTES.md` per ticket directory** is a real convention, not an option: all
four `templates/<jira-id>/` directories on `main` carry one. The scaffold emits
a stub, and `lint` requires it — it is where the per-ticket target reasoning
lives, and its absence is what made VSRV-1665's company-id mismatch invisible.

## Subcommands

| Slash command | What it does | Output | Implementation |
|---|---|---|---|
| `/sre-migration-scaffold <name>` | Generate a six-operation tool skeleton plus one input sample per environment | `extend/scripts/<name>/` | `scaffold/IMPL.md` |
| `/sre-migration-draft <STORY-ID>` | Fetch the template, draft the ticket body and per-env command flow (Chinese) | `migration-ticket.md`, `command-flow.md` | `draft/IMPL.md` |
| `/sre-migration-lint <STORY-ID>` | Gate the draft against the checks below; report high-risk inputs | stdout report | `lint/IMPL.md` |
| `/sre-migration-ticket <STORY-ID>` | Create the VSRV issue from the linted draft | Jira issue key | `ticket/IMPL.md` |

**There is no `--kind`.** The earlier `rds|api` split was derived from a sample
of two tools; `main` now has three, and the third
(`update-cognito-unverified/`, AWS-CLI-driven, no items file, no `templates/`)
does not fit either label. What all three genuinely share is the enforcement
shape — dry-run by default, `--apply` to mutate, `--yes` for automation — and
they differ only in the operation bodies, which the author writes anyway. One
skeleton, no kind axis: a flag whose values cannot cover the known cases is
worse than no flag.

`/sre-migration-draft` writes Chinese bodies, per the standing carve-out for
requested-Chinese deliverables. Everything else in the skill is English.

**`draft` and `lint` share one template file.** The ticket body skeleton lives
in `draft/templates/migration-ticket.md.tmpl`, not in a heredoc inside
`draft/IMPL.md`. `lint` reads the same file to learn which sections and per-
operation sub-fields must be present. One source means the linter cannot drift
from the drafter — a check that silently stops matching a renamed section is
the failure this prevents.

## What the scaffolded tool must enforce

`/sre-migration-scaffold` generates a tool that touches production data, so two
guarantees are part of the skeleton rather than left to whoever fills in the
operation bodies:

- **Dry-run by default.** `migrate`, `rollback`, and `restore` print the
  statements and the computed after-state and change nothing unless `--apply`
  is passed, with a typed confirmation on top of it. Fail closed: the absence
  of a flag must never mean "write".
- **Refuse unbounded destructive SQL.** A generated `UPDATE` or `DELETE` with
  no bounded `WHERE`, and any `DROP`/`TRUNCATE`, aborts rather than executing —
  regardless of `--apply`. Bounded means keyed on the specific ids the items
  file names.

All three shipped tools already dry-run by default and mutate only on
`--apply` — including `update-cognito-unverified`, whose header says so
explicitly. That consistency is the argument for encoding it: three authors
reached the same convention independently, and nothing but habit stops the
fourth from omitting it. `lint`
does not check these; they are properties of generated code, so their tests
live with the scaffold.

## Lint checks

Each traces to a recorded rejection or a template rule, not invented hygiene:

| id | Check | Source |
|---|---|---|
| `sha-on-main` | Referenced commit SHA is on `main` | VSRV-2487 |
| `not-provided-contradiction` | No operation declares `是否提供: No` while dev output for it is attached | VSRV-2487 |
| `empty-operation` | Every provided operation has a non-empty `說明` and a command block | VSRV-2527 |
| `idempotency-answered` | Every `可否重複執行` is answered | Template |
| `company-id-guard` | Every `company_id` in the body matches the samples' `expected_*` guards | VSRV-1665 |
| `unit-drift` | Units are consistent (days vs pcs) | VSRV-1665 |
| `env-samples-complete` | A sample exists for every env the tool's `--site` accepts, env-prefix named — or the tool declares it takes no items file | Three shipped tools |
| `no-prod-in-lower-env` | No prod identifier appears in a lower-environment sample | Template |
| `six-operations` | All six operations addressed (`restore` present or justified) | Template |
| `pii-answered` | PII answered as Yes/No/不確定 with data types named | Template |
| `notes-present` | `templates/<jira-id>/NOTES.md` exists and names the target | 4/4 on `main` |
| `high-risk-inputs` | High-risk **inputs** reported for a human decision | Template |

Each id is the name of its fixture pair under `lint/tests/fixtures/<id>/`
(`bad.md` must produce a finding naming that id and a non-zero exit; `good.md`
must produce neither). A check with no fixture pair is not implemented — see
Testing.

## Jira mechanics

Issue type `Change Request - Migration Execution` **is** creatable in the SRE
project, as a top-level type (`subtask=false`). The earlier "only 12 of 27
issue types" reading was plain pagination — `maxResults=100` returns all 27. So
`/sre-migration-ticket` files the issue rather than degrading to paste-ready text.
(Confirmed from `createmeta` only; no test issue was filed.)

Required fields are just `project`, `summary`, and **Platform Service** — a
custom field whose value is an option: VORTEX / RESELLER / VORTEXAI.
Description is optional.

Resolve the project id, issue-type id, and the Platform Service custom-field id
**at runtime** from `createmeta`, keyed by name. Do not pin the numeric ids
here: they are site-specific and can be re-pointed the same way the wiki host
was, which is the failure this design exists to avoid.

`SRE Pre-check`, `SRE Stage Record`, and `SRE Prod Record` are **three separate
custom fields filled by SRE**, not Description sections. Both shipped
`migration-ticket.md` drafts render them as `##` body headings, which is wrong.
`/sre-migration-ticket` sets them as fields, left empty for SRE, and lint stops
expecting them in the body.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Template source | Story folder artifact first, fetch as fallback and cache into the story | `a4cd5da4` checked it in; re-fetching duplicates intake and needs credentials |
| Wiki host (fallback only) | Derive from page URL; Jira credential when it equals `$JIRA_HOST` | A stored copy can drift from `JIRA_HOST`; that drift is the original failure |
| High-risk | Report inputs, never a verdict | Sign-off is a human judgment with a management step attached |
| Docker | Deferred, rules recorded | Pending decision; blocks nothing else in the skill |
| `--kind` | Removed | Three shipped tools, and the newest fits neither `rds` nor `api` |
| Environment set | Deployed trio (dev/stage/prod), `NOTES.md` may exempt one | Deriving it from `--site` flags 2 of 4 shipped dirs |
| Sample naming | Env-prefix only | Rule 7 — pick one, flag the other, do not hybridise |
| `restore` in shipped tools | Flag, do not retrofit | They are merged and reviewed; that is its own change |

## Files

```
skills/sre-migration/
  SKILL.md                                  # router: subcommand table, output paths + IMPL pointers
  scaffold/IMPL.md
  scaffold/templates/                       # six-op skeleton, one sample per env
  scaffold/templates/items-file.schema.json # validated by the tests
  draft/IMPL.md
  draft/templates/migration-ticket.md.tmpl  # read by BOTH draft and lint
  lint/IMPL.md
  lint/lib/lint.sh                          # the executable gate: --check <id> <ticket.md>
  lint/tests/test_lint.sh                   # fixture-pair runner
  lint/tests/fixtures/<check-id>/bad.md     # one pair per lint check, named for its id
  lint/tests/fixtures/<check-id>/good.md
  lint/tests/fixtures/company-id-guard/{bad,good,other-tool,exempt,undocumented}-items/  # trees
  lint/tests/fixtures/notes-present/{good,bad,partial,devonly}-items/, missing-notes/   # trees
  ticket/IMPL.md
  tests/test_sre_migration.sh
registry.txt                                # + local sre-migration
```

`SKILL.md`'s table carries both the artifact path and the `IMPL.md` pointer,
per commit `90b3429` — its audit found seven skills whose `SKILL.md` gave an
agent no textual path to the recipe.

Every path named anywhere in this spec appears in the tree above, and vice
versa. Keep it that way: the prior art rejected below states "link every
referenced bundled file and verify it exists" and then ships two references to
files that do not exist, which is what makes its guidance unusable.

## Testing

- `tests/test_sre_migration.sh`, run by `run-tests.sh`, in the style of
  `skills/jira/tests/test_jira.sh`.
- **Lint tests are the substance, and they are the gate.** Every one of the 12
  checks gets a should-flag / should-not-flag fixture pair named for its id.
  A check is only real once `lint/lib/lint.sh` implements it: nine are
  executable (six read the ticket body alone, plus `sha-on-main` against a
  throwaway git repo, and `company-id-guard` and `notes-present` against fixture
  trees of sample files), and three needing further environment state are
  agent-performed until their fixtures grow trees. A check that cannot run must exit 2 or report N/A,
  never 0 — a skipped check reading as clean is the failure mode.
- **A check needs an exemption path wherever the repo already records one.**
  `company-id-guard` reads the ticket's `NOTES.md` and reports `EXEMPT` with the
  quoted reason instead of `FAIL`, because a null guard is sometimes the correct
  choice and one shipped file documents exactly that. Three false-positive
  classes were found only by running against real artifacts — the accepted
  tickets, another tool's input shape, and this documented null. Validating a
  check against its own fixtures proves nothing; every check must be run against
  the real files before it is believed. `lint/IMPL.md` must keep
  saying which is which. The operation list is parsed from
  `draft/templates/migration-ticket.md.tmpl`, so renaming an operation there
  changes what lint checks — verified by test, not by convention.
  The should-not-flag half is not optional: false-positive suppression is half
  of what a linter can regress, and a check that fires on everything is as
  useless as one that fires on nothing. Assert three things per pair — exit
  code, that the finding names the offending item, and that it does *not* name
  a sibling item that is legitimately fine.
- The three recorded rejections supply real fixtures rather than invented ones:
  VSRV-2487 for `not-provided-contradiction` and `sha-on-main`, VSRV-2527 for
  `empty-operation` (its filed ticket is the `bad.md`; the `good.md` is authored
  from the tool's "End-to-end flow, per environment" section in
  `README-inventory-v2-correction.md` on `main`, which is what the discarded
  hand-written flow was itself derived from), VSRV-1665 for `company-id-guard`
  and `unit-drift`.
- Validate every items-file sample against `items-file.schema.json`, and assert
  the schema itself requires the guard fields.
- Test the scaffold's two enforced guarantees directly: scaffold a throwaway
  tool into a temp dir, then assert its `migrate` writes nothing without
  `--apply` and that an unbounded `UPDATE`/`DELETE` aborts. Clean up in a trap
  so a failure cannot leave the temp dir behind.
- No judge-based evals in v1. A quality rubric is worth adding only for whether
  a finding's *wording* would satisfy an SRE reviewer; everything else these
  checks assert is deterministic and belongs in bash.
- Assert no recipe builds a repo path from an undefined variable
  (`.claude/hooks/skill-paths-guard.sh`, commit `5305ca8`).
- Assert no hostname or numeric Jira id is hardcoded: recipes must reference
  `$JIRA_HOST` / `$CONFLUENCE_HOST` and resolve ids by name at runtime. This
  repo is public — real hosts, customer identifiers, and account names belong
  in `config.sh` and the work repo, never in a recipe or a spec.

## Prior art assessed

`harness-creator` (a third-party course skill, read in full 2026-09-01) was
evaluated as a possible authoring standard and **rejected** as one. It builds
agent *harnesses* — `AGENTS.md`, `feature_list.json`, `progress.md`, `init.sh`
— not subcommand skills, so it offers no path to this layout; its runtime is
Node, which none of this repo's four Stop guards cover; and it fails its own
stated rule that every referenced bundled file must exist. Four ideas were
taken from it and are already folded in above: the templates/tests separation,
the protected-destructive-command list, fail-closed defaults, and a JSON schema
for a generated artifact. Two were explicitly declined: its eval case format
(no machine-vs-judge discriminator, no fixture polarity — strictly weaker than
a bash assertion for gate use) and its i18n file variants.

## Open

- Docker packaging, above.
- Whether the shipped tools eventually gain `restore` and a Dockerfile, or stay
  as they are with the divergence documented.
