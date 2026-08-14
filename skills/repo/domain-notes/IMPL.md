---
subcommand: domain-notes
group: repo
slash: /repo-domain-notes <query|add> [args]
output: ./.spec-gated/domain-notes.md (target repo root — persists across stories)
---

# repo/domain-notes — Domain Notes Cache

Accumulates architecture facts discovered while working stories, so the next
story doesn't repeat the same git archaeology or code reading. Complements
`/repo-context-scan` (per-story, thrown away after the story ships) with a
persistent, cross-story knowledge base scoped to the repo itself.

This is the "Memory" capability of a Deep Agent applied to repo knowledge:
architecture facts that were expensive to discover (removed modules,
permission-check call chains, migration history, naming quirks) get written
down once instead of re-discovered by git archaeology every time a similar
story comes up.

## When to use

```
Starting an investigation into legacy/removed code, permission mapping, or
non-obvious architecture → /repo-domain-notes query <keyword> FIRST, before
grep/git archaeology.

Investigation surfaced a non-obvious fact that will matter again (removed
module, auth/permission logic, migration history, naming quirk) →
/repo-domain-notes add AFTERWARD, before closing out the story.
```

Typical position in the workflow:

```
/intake-jira-story <STORY-ID>
/repo-domain-notes query <keyword>       ← check cache before digging
/repo-context-scan <STORY-ID>            ← still run this; notes are a shortcut, not a replacement
  ... investigation, git archaeology if cache missed ...
/repo-domain-notes add                   ← write down what was learned
/audit-domain-risk <STORY-ID>
```

## Storage

`./.spec-gated/domain-notes.md` in the target repo root — same directory as
the `domain-risk-checks.md` override used by `audit/domain-risk`. One file
per repo, not per story. Whether the team commits this file or gitignores it
is their call; the skill doesn't enforce either.

## query <keyword>

```bash
NOTES=./.spec-gated/domain-notes.md
if [[ ! -f "$NOTES" ]]; then
  echo "DOMAIN_NOTES_STATUS: MISS (no notes file yet)"
  exit 0
fi

MATCH=$(grep -B1 -A6 -i "$1" "$NOTES")
if [[ -n "$MATCH" ]]; then
  echo "DOMAIN_NOTES_STATUS: HIT"
  echo "$MATCH"
else
  echo "DOMAIN_NOTES_STATUS: MISS (no entry matched '$1')"
fi
```

The `DOMAIN_NOTES_STATUS` line is a machine-checkable marker — it's what lets
an eval pass over the transcript later and confirm hit/miss mechanically
instead of a human re-reading the whole exchange. Always emit it, on every
run, before anything else.

Read whatever matches. Treat entries as **hints, not facts** — code moves on,
notes don't update themselves. Each entry records the commit it was verified
at (`Verified at commit: <sha>`). Compare it against the current HEAD:

```bash
git rev-list --count <verified-sha>..HEAD 2>/dev/null
```

If that count is large (rule of thumb: >20 commits, or the note is
project-critical), do a quick spot-check (grep the referenced file/function
still exists, matches the described behavior) before relying on the note
instead of trusting it blindly. Print `DOMAIN_NOTES_STATUS: SPOT_CHECK_DONE`
or `DOMAIN_NOTES_STATUS: SPOT_CHECK_SKIPPED (n commits behind)` so this
decision is also visible in the transcript, not just made silently.

If the keyword search finds nothing (`MISS`), fall back to normal
investigation (grep, `git log -S`, `git show`) — the cache is a shortcut,
not a guarantee.

## add

No rigid CLI — construct the entry directly and append it to `$NOTES`. Never
overwrite existing entries; only append. Create the file with the header
below if it doesn't exist yet.

```bash
NOTES=./.spec-gated/domain-notes.md
mkdir -p "$(dirname "$NOTES")"
if [[ ! -f "$NOTES" ]]; then
  REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "this repo")
  cat > "$NOTES" <<EOF
# Domain Notes: $REPO_NAME

Accumulated architecture facts learned while working stories. Treat entries
as hints — verify against current code before relying on a stale one.

---
EOF
fi

COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
DATE=$(date +%Y-%m-%d)
```

Then append one entry using the template in **Output format** below, filling
in the real title, tags, fact, commit, and source story. Keep facts specific
and actionable — name the actual function/file/rule, not a vague summary.

After appending, print a confirmation line an eval pass can grep for:

```bash
echo "DOMAIN_NOTES_STATUS: APPENDED (title: <short title>, tags: <tag1,tag2>)"
```

## Output format

Each entry follows this shape (append, don't replace existing entries):

```markdown
## <YYYY-MM-DD> — <short title> [tags: tag1, tag2]
<2-6 sentences: the specific fact — function names, file paths, the actual
rule. Write it so the next agent can act on it without re-reading the code.>

Verified at commit: <short-sha>
Source story: <JIRA-ID or "n/a">

---
```

Example (from a real investigation):

```markdown
## 2026-08-11 — vortex/organization API permission mapping [tags: auth, vortex, organizations]
`internal/feature/{vortexfeature,vortexapifeature,addbundlistfeature}` was
fully removed (commit 6eba17f18, #613) and replaced by `internal/service` +
`internal/repo` layers. Permission checks now live in `ValidatesService`
methods called directly from `internal/controller/{organizations,vortex}/*.go`:
- `IsServiceOrg(ctx, sub, orgId)` — sub is a member of the org's service vendor company
- `IsUserCompany(ctx, sub, companyId)` — requester belongs to that exact company
- `IsCompanyTypeBySub(ctx, sub, []uint{...})` — gate by company type (HQ_PM=1, HQ_Sales=2, Region=3, Disty=4, Dealer=5)
- `IsOrgServiceCompanyParent` — HQ_PM, or the upstream company of the org's service vendor
- `CanVortexToken` — HQ_PM (any), HQ_Sales/Region (same region only), Dealer (own company only)

Verified at commit: 6eba17f18
Source story: VOR-31324

---
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Treating an old note as still true | Spot-check against current code (grep the function/file still matches) before relying on it, especially if many commits have passed since `Verified at commit` |
| Writing vague facts ("auth is complex here") | Name the actual function, file, and rule — vague notes don't save the next investigation any time |
| Skipping the tags field | Tags are what makes `query <keyword>` actually find the entry later — always include at least one |
| Logging one-off facts that won't recur | Only add facts likely to matter again: removed modules, permission/auth logic, migration history, non-obvious naming. Skip anything story-specific that belongs in `repo-context.md` instead |
| Overwriting the file instead of appending | Always append — this file accumulates across every story ever worked in the repo |
