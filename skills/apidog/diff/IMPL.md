---
subcommand: diff
group: apidog
slash: /apidog-diff <STORY-ID>
output: stdout only
---

# apidog/diff — Contract vs Live State Diff

Compares the local contract markdown against the live Apidog project state.
Use after `/apidog-contract` to verify the push succeeded, or before
implementation to confirm Apidog is in sync with the spec.

## Prerequisites

```bash
source ~/.agent-skills-setup/lib.sh
STORY_DIR=$(resolve_story_dir "$1") || exit 1
[[ -f "$STORY_DIR/apidog/contract.md" ]] || { echo "ERROR: run /apidog-contract first" >&2; exit 1; }
```

## Step 1 — MCP prerequisite check

```
apidog_modules()
```

If this fails, tell the user to run `/infra-apidog-mcp setup` first.

## Step 2 — Export live state from Apidog

```
apidog_export(module: <module-name>)
```

This returns the current OpenAPI spec from Apidog for the target module.

## Step 3 — Convert local contract to OpenAPI

Convert `$STORY_DIR/apidog/contract.md` to an OpenAPI 3.0 spec (same format
used by `/apidog-contract` Step 3 when pushing).

## Step 4 — Run diff

```
apidog_diff(
  localSpec: <openapi-from-contract-md>,
  module: <module-name>
)
```

The MCP tool compares the local spec against the live Apidog state and
returns a structured diff.

## Step 5 — Report

Print a summary to stdout:

```
Apidog diff for <STORY-ID>

  Matching endpoints : <n>
  Missing in Apidog  : <list of paths>
  Extra in Apidog    : <list of paths>
  Schema drift       : <list of paths with response/request differences>

Status: IN SYNC  /  OUT OF SYNC
```

If out of sync:
- Missing in Apidog → run `/apidog-contract <STORY-ID>` to re-push
- Extra in Apidog → manual cleanup needed in Apidog UI (no delete-by-story API)
- Schema drift → review and re-push with `apidog_update` or full re-import

Do not auto-fix drift. Report only. Let the user decide.
