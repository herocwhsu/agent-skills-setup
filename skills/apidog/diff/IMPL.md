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

Check if the user passed a share link alongside the STORY-ID (e.g., as a second argument or in the story's `intake-summary.md`):

```
If URL matches share.apidog.com/<uuid>:
  → Use Share REST API (see below) — skip MCP prerequisite check
Else:
  → Use MCP apidog_export (existing path)
     Run apidog_modules() first; if it fails, tell user to run /infra-apidog-mcp setup
```

### Share REST API path

```bash
UUID=$(echo "$SHARE_URL" | grep -oE '[0-9a-f-]{36}')
SHARE_API="https://api.apidog.com/v1/shared-docs/${UUID}/export-openapi"

HTTP_CODE=$(curl -s -o /tmp/_apidog_live.json -w "%{http_code}" "$SHARE_API")

if [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
  echo "Share link is password-protected."
  printf "Enter share password: "
  read -r SHARE_PASS
  HTTP_CODE=$(curl -s -o /tmp/_apidog_live.json -w "%{http_code}" \
    -H "X-Apidog-Share-Password: $SHARE_PASS" "$SHARE_API")
  unset SHARE_PASS
fi

[[ "$HTTP_CODE" != "200" ]] && {
  echo "ERROR: Apidog share export returned HTTP $HTTP_CODE" >&2; exit 1
}
# /tmp/_apidog_live.json now contains the live OpenAPI spec
```

### MCP path (default)

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
