---
subcommand: scaffold
group: sre-migration
slash: /sre-migration-scaffold <name>
output: extend/scripts/<name>/
---

# sre-migration/scaffold — Generate a conforming correction tool

Generates the skeleton of an SRE correction tool: six operations, one input
sample per environment, a schema, and a `NOTES.md` stub.

## Overview

The ticket template requires six operations and a per-operation idempotency
declaration. Writing that by hand means rediscovering it each time, and the
three tools already on `main` each diverge from it differently. The scaffold
fixes the shape; the author fills in the bodies.

**There is no `--kind` flag.** An earlier design split `rds` vs `api`, derived
from a sample of two tools. The third (`update-cognito-unverified/`) is
AWS-CLI-driven with no items file and fits neither label. What all three share
is the enforcement shape, so one skeleton covers them; the operation bodies
differ, and the author writes those regardless.

## Steps

### Step 1 — Confirm nothing reusable exists

Do not scaffold a new tool for a ticket an existing one can serve. Adding a
`templates/<jira-id>/` sample set to an existing tool is the common case:

```bash
ls extend/scripts/
```

Scaffold only when the operation bodies genuinely differ from every existing
tool. Say which existing tool you ruled out and why.

### Step 2 — Generate the skeleton

Create `extend/scripts/<name>/` containing:

| File | Purpose |
|---|---|
| `<name>.sh` | The tool. Six operations dispatched from one argument. |
| `<name>.test.sh` | Its tests, in the style of the sibling tools' `*.test.sh`. |
| `README-<name>.md` | Usage, including an end-to-end flow per environment. |
| `templates/README.md` | What a sample file means and how to add a ticket dir. |
| `templates/<name>-template.json` | The generic sample, with null targets. |
| `templates/items-file.schema.json` | Schema for every sample file. |

### Step 3 — The six operations

Emit all six, each as its own dispatchable operation:

| Operation | Must do |
|---|---|
| `precheck` | Verify preconditions, print the target's identity, output affected row count. Read-only. |
| `backup` | Snapshot the rows the change will touch, into their own directory. Read-only. |
| `migrate` | The change. Dry-run unless `--apply`. |
| `verify` | PASS/FAIL on the result. Read-only. |
| `rollback` | The logical inverse (e.g. UPDATE back to the prior value). |
| `restore` | Whole-restore from `backup`'s output. **Not the same as `rollback`.** |

An operation the tool genuinely cannot provide still appears, exiting with a
message naming why. A silently missing operation is what the ticket's
`是否提供: No` declaration exists to cover, and lint cross-checks the two.

### Step 4 — Enforce fail-closed behavior in the generated code

Two guarantees belong in the skeleton, not in the author's discretion:

```bash
# Dry-run is the default. --apply mutates; --yes skips the confirmation prompt.
# The ABSENCE of a flag must never mean "write".
if [[ "$APPLY" != "yes" ]]; then
  echo "dry-run: would execute the statements above; nothing was changed"
  exit 0
fi

# Refuse unbounded destructive SQL regardless of --apply.
case "$STATEMENT" in
  *DROP*|*TRUNCATE*)         echo "refusing: DROP/TRUNCATE is out of scope" >&2; exit 2 ;;
esac
if [[ "$STATEMENT" =~ ^[[:space:]]*(UPDATE|DELETE) ]] && [[ ! "$STATEMENT" =~ WHERE ]]; then
  echo "refusing: UPDATE/DELETE with no WHERE clause" >&2
  exit 2
fi
```

Bounded means keyed on the specific ids the items file names. All three shipped
tools already dry-run by default — three authors converged on it independently,
which is the argument for encoding it rather than trusting the fourth to
remember.

### Step 5 — One sample per deployed environment

Emit one sample for each of `dev`, `stage`, `prod`.

Do not try to read the environment list from the tool's `--site` flag here: this
subcommand is *creating* that tool, so the flag does not exist yet. And do not
emit a `local` sample — `--site local` points at `http://localhost:8080`, a
developer's own machine, which needs no checked-in target file. One shipped tool
accepts `local` and ships no local sample.

Filenames are env-prefixed: `<env>-<target>-<action>.json`.

Every sample carries the guard fields that make a wrong target fail loudly
rather than silently corrupt data:

```json
[
  {
    "company_id": null,
    "expected_name": null,
    "expected_ship_to_code": null
  }
]
```

`expected_name` / `expected_ship_to_code` are required by the schema. A sample
that omits them disables the guard while still looking complete.

### Step 6 — `NOTES.md` stub

Every `templates/<jira-id>/` directory carries one (4/4 on `main`). It records
how the target was resolved — which query, in which environment, on what date.
Company ids are per-environment auto-increment, so an id confirmed in one
environment means nothing in another.

## Common Mistakes

| Mistake | Why it matters |
|---|---|
| Scaffolding when an existing tool would serve | Duplicated tools drift; a ticket dir on the existing tool is cheaper |
| Omitting `restore` because `rollback` exists | They are different operations; the template names both |
| Emitting a `local` sample | `local` is a developer's own machine, not a deployed target |
| Leaving `expected_*` out of a sample | The guard silently stops protecting the target |
| Writing the tool without its `*.test.sh` | `coverage-check.sh` reports it, and the sibling tools all ship one |
