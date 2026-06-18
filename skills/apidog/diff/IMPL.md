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

## Step 1 — Determine live state source

Pick the read path based on what the user is comparing against:

| Target | Read path | Why |
|---|---|---|
| Default branch (project main) | MCP `apidog_export(module: ...)` | Native, single round-trip, branch-aware writes still possible |
| Non-default branch (e.g. Sprint 90) | `scripts/apidog-share-fetch.py` against the branch's public share link | MCP has no branch support and Apidog REST `/v1/shared-docs/<uuid>/export-openapi` redirects to docs (verified 2026-06-18) — the share link's Remix loader is the only working read path |
| Single endpoint on any branch | `scripts/apidog-share-fetch.py --endpoint-id N` | Same as above, faster than full export |

The user passes the share UUID either as a second CLI argument or in `intake-summary.md`'s `apidog_share_uuid:` frontmatter. Without one, fall back to MCP and warn that only the default branch is being compared.

### Share-link path (non-default branch)

```bash
SHARE_UUID=$(echo "$SHARE_URL" | grep -oE '[0-9a-f-]{36}')
SCRIPT="$REPO_DIR/scripts/apidog-share-fetch.py"

# Pull every endpoint matching the contract's path prefix
python3 "$SCRIPT" --share-uuid "$SHARE_UUID" --path-prefix "$CONTRACT_PATH_PREFIX" \
  > /tmp/_apidog_live.json

[[ -s /tmp/_apidog_live.json ]] || {
  echo "ERROR: share-fetch returned empty result for $SHARE_UUID" >&2; exit 1
}
```

The script's output is a JSON array of normalized endpoints — each has `id`, `method`, `path`, `name`, `status`, `description`, `request`, `responses` (with `type_enums` extracted from `x-apidog-overrides`). This shape is what Step 4's diff logic compares against.

### MCP path (default branch only)

```
apidog_export(module: <module-name>)
```

Returns the current OpenAPI spec from Apidog for the target module on the default branch only.

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
