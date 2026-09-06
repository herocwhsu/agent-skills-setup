# Design: split we-skills out of agent-skills-setup

**Status:** Approved for planning
**Date:** 2026-09-06

## Goal

Two repos coexisting on one machine: `agent-skills-setup` (team) and `we-skills`
(personal, public). Overlapping skill names are fine — reinstalling flips the
symlink and that is the intended way to switch. What must NOT overlap is
per-repo state: config, installed-skill records, and credentials, because the
two carry **separate accounts** for Apidog, Anthropic, Gemini and Linear.

## Why this is two sub-projects

Sub-project 1 fixes a latent bug in the current repo. Sub-project 2 creates the
new one. Doing 1 first means 2 inherits correct behavior instead of encoding the
bug twice.

---

## Sub-project 1 — per-repo runtime state (in `agent-skills-setup`)

### The bug

`.skills-repo-id` (added by `aff4ed4`) identifies a tree correctly, but there is
only one place to keep it: `install_runtime_dir` writes to a hardcoded
`$HOME/.agent-skills-setup` (`scripts/_lib.sh:439`). With two repos installed the
second install overwrites the first's marker, and afterwards the older repo's
skills resolve to the sibling's tree.

Verified: with skill names deliberately made distinct so the name collision could
not confound it, `setup_repo_dir` sourced from the shared `lib.sh` returned
`we-skills` for a skill belonging to `agent-skills-setup`.

Blast radius is narrower than it first appears — exactly one runtime call site
(`skills/apidog/diff/IMPL.md:40`). The real damage is shared state:

| Shared file | Consequence |
|---|---|
| `config.sh` | one `JIRA_HOST` / `CONFLUENCE_HOST` / `JIRA_PROJECT_KEY` / `APIDOG_*` for both repos |
| `installed.txt` | `install.sh:71` truncates it, so installing one repo erases the other's record and a later `uninstall.sh` cannot know what it installed |
| keychain prefix | `_KEYCHAIN_PREFIX` is a bare literal, so both repos read the same credential slugs |
| `.skills-repo-id` | the wrong-tree case above |

### The change

Derive the runtime dir, the keychain prefix and the JSON fallback path from
`.skills-repo-id`, falling back to `agent-skills-setup` when no marker exists
(pre-marker hosts keep working, as `setup_repo_dir` already does).

This repo's id **is** `agent-skills-setup`, so its derived path is byte-identical
to the hardcoded one: no migration, no state moves, behavior unchanged. Only a
differently-named repo gets its own dir.

Sites, all of which must land together — `install.sh:67` *sources* `lib.sh` from
the literal path, so changing `install_runtime_dir` alone writes `lib.sh` to the
new dir and then dies sourcing the old one:

- Runtime path, 9 platform files: `lib/lib.sh`, `scripts/_lib.sh`,
  `scripts/install.sh`, `scripts/update.sh`, `scripts/credentials/_store.sh`,
  `scripts/credentials/service.sh`, `scripts/skill-path-var-check.py`, and the
  two test files that build their own runtime dirs.
- Prefix definitions, 2 independent: `scripts/credentials/_store.sh:16`
  (`_KEYCHAIN_PREFIX`) and `:34` (`_FALLBACK_STORE`), plus
  `skills/utils/confluence-tree/lib/cred_provider.py:19` (a third, in Python).
- Prefix literals, 13 in this repo: `kiro-gateway.sh` (7),
  `kiro-gateway/README.md` (2), `polish_engine.py` (2), `apidog-mcp/IMPL.md` (2).
  we-skills inherits only 4 of these, since it does not carry kiro-gateway.
  These bypass
  `require_secret`/`read_secret`; left as literals in a copy they would read the
  *team* credential while sibling recipes read the personal one — a split-brain
  that fails silently.

`_store.sh` cannot currently derive anything: it has no `BASH_SOURCE`/`_LIB_DIR`.
It must self-locate and read the marker beside itself, the way `lib.sh` already
does via `_LIB_DIR`.

Ship the `installed.txt` truncation fix here: each repo truncates its own record.

### Out of scope, deliberately

`install-agents-md.sh:35-36` wraps deployed rules in
`<!-- BEGIN agent-skills-setup:engineering-rules -->`. That is a block marker in
`~/.claude/CLAUDE.md`, not a credential namespace, and sharing it is correct —
distinct markers would stack two rule sets in one file. Left alone.

---

## Sub-project 2 — create `we-skills`

### Provenance

Fresh `git init`. Not a clone, not a filtered copy: `your-org.atlassian.net`,
`confluence.example.com`, a personal Gmail address and a Vault address each
appear in 2–5 commits of `agent-skills-setup`'s **public** history, and any
clone carries that forward. Nothing is cherry-picked between the two afterwards,
which is why diverging the 55 `skills/` files that hardcode the runtime path
costs nothing.

### Approach: copy, then transform

Copy the carried tree, run one scripted transform, commit once. The transform is
auditable and re-runnable; `harness-verify.sh` plus the 46 tests catch a bad
pass. Rejected alternative: port skill-by-skill. That only pays off if the
skills get reshaped rather than copied, which is not the goal.

Transform: marker → `we-skills`; runtime paths and prefixes → derived; org
values → env/config placeholders.

### Carried

- **Platform** — all of `scripts/` except `test-polish-endpoint.sh` (deleted in
  `c0e6dbc`), `lib/lib.sh` (10 functions), `scripts/credentials/`, `hooks/`,
  `.claude/hooks/` + tests, `.github/workflows/test.yml`, `mypy.ini`,
  `ruff.toml`, `.gitignore`, `registry.txt`, `AGENTS.md` and `README.md`
  (rewritten for the new repo).
- **Story flow** — `intake`, `audit`, `repo`, `external`, `testing`, `jira`,
  `review`, `release`, `progress`, `apidog`, plus `npm @fission-ai/openspec`
  for the archive step.
- **External sources** — registry types `github`, `github-skill`, `plugin`,
  `plugin-optional`, `npm` and their install/uninstall functions. This is how
  `obra/superpowers` already arrives.
- **Generic skills** — `infra/ups`, `infra/tmux-yank`,
  `infra/host-optimization`, `infra/apidog-mcp`, `utils/polish-input`,
  `utils/skill-eval`, `ai-stack`, `experiment-iteration`.

### Not carried

- `sre-migration` — org SRE work.
- `infra/kiro-gateway` — manages a Docker proxy built from a **patched personal
  fork** (`README.md:8` requires SSH access to `git@github.com:herocwhsu/kiro-gateway.git`,
  and the 3 patches apply only to that upstream). A public repo should not ship
  tooling whose default target is a private fork. Removing it is not just
  deleting `skills/infra/kiro-gateway/` (8 files, 3 of which carry a personal
  email in `From:` headers) — it is a **subcommand of the `infra` skill**, so the
  transform must also edit: `skills/infra/SKILL.md` (frontmatter description,
  subcommand table, decision tree, state table, install-path notes),
  `skills/README.md:46` (the infra row), `docs/migration.md`, and
  `scripts/setup-credentials.sh:18,52` — a platform file that offers
  `kiro-gateway` as credential menu option 6. Note that `kiro-gateway` is absent
  from `service_def()` in `service.sh`: it stores its key directly via
  `security add-generic-password` (`kiro-gateway.sh:101-102`) rather than through
  the service table, so the menu entry and the table are already inconsistent in
  this repo. Verify where option 6 routes before deleting it.
- `migrate_keychain` (`lib/lib.sh:244`, called at `install.sh:68`) — renames a
  legacy `agent-skills:*` prefix to a hardcoded `agent-skills-setup:*`. The
  legacy entry count on this host is **0**, so it is dead code; in we-skills it
  would migrate *into the team namespace*.
- `docs/superpowers/` plans and specs — development history of that repo. Keep
  `ai-learning-charter.md`, `experiment-template.md`, `spec-gated-workflow.md`,
  `migration.md`.
- `scripts/tests/fixtures/apidog-share-10000001.data` — a real share dump
  containing org data. Needs a synthetic replacement, and `.gitleaksignore`
  updated to match.

### Confluence: what carries, and what each part provides

`utils/confluence-tree` **is carried.** An earlier draft of this design called it
"built around one Confluence instance" — that was wrong. It reads `CONFLUENCE_HOST`
and `CONFLUENCE_USER` from `config.sh` throughout, and `charter.md:105` already
forbids hardcoded URLs. The only instance-specific residue was two copies of a
past migration job's page ID in `upload_resume.py`, fixed in `453e3f6`:
`--fetch-dir` is now required with no default, matching `tree_fetch.py --out-dir`
and `link_rewrite.py --out`.

Read and write come from different skills, which matters if the scope ever
narrows again:

| Capability | Provider |
|---|---|
| Read a Confluence page | `intake/web-page` — its own `curl -u` against `/rest/api/content`, via `service_slug` + `require_secret`. `intake/` contains zero POST/PUT. |
| Create / update / attach | `confluence-tree` only — every write in the repo lives here (`push.py:89`, `tree_upload.py:112,145`, `attach.py:89`, `upload_resume.py:87`) |

So dropping confluence-tree would have cost writes and nothing else; carrying it
keeps both. Credentials are unaffected either way — `service.sh` and the keychain
entry are platform, not part of the skill.

**Known limitation, carried as-is:** confluence-tree is documented self-hosted
**Server/DC only** (`IMPL.md:3`, `README.md:11`, `charter.md:13`). `base_url()`
prepends `https://` and callers append `/rest/api/...`; Confluence **Cloud**
serves `/wiki/rest/api`, and there are zero `/wiki/rest` references in `skills/`.
The only Confluence credential on this host is the team's self-hosted instance,
while the personal Atlassian site (`dibts3.atlassian.net`) is Cloud. Passing
`CONFLUENCE_HOST=<site>/wiki` would plausibly produce correct Cloud paths, since
`base_url()` accepts a full base URL — but auth differs (Cloud wants email + API
token, and the PAT-shape autodetect at `attach.py:52` may guess wrong) and
several documented behaviors are Server-specific (`ac:structured-macro` → 501,
unique-title-per-space). Untested against a live Cloud instance. Treat Cloud
support as separate work, not part of this split.

---

## Credential migration

### What needs migrating, and what does not

Prefixing means the team repo needs **no** migration: all five existing entries
keep working under `agent-skills-setup:*`. Migration exists only so personal
tokens need not be retyped into `we-skills:*`.

Entries on this host, and how confidently their owner can be inferred:

| Entry | Inference |
|---|---|
| `jira-https---vivotek-atlassian-net` | host-keyed → team |
| `jira-https---dibts3-atlassian-net` | host-keyed → personal |
| `confluence-https---confluence-vivotek-com` | host-keyed → team |
| `apidog` | bare name → **unknowable** |
| `kiro-gateway` | bare name → **unknowable** |

Host-keyed slugs are self-labelling. Bare-name slugs are not: no tool can tell
whose account `apidog` holds. So the migration must show each entry and let the
user decide, rather than guess — copying the team Apidog token into the personal
namespace is precisely the silent split-brain this split exists to prevent.

### Design

`scripts/migrate-credentials.sh`, carried by both repos (it is generic: copy
credentials from another repo's prefix).

- `--from <prefix>` defaults to `agent-skills-setup`; destination is the running
  repo's derived prefix.
- **Dry-run is the default.** It lists each source entry, classified as
  *host-keyed (suggested)* or *bare name (needs a decision)*, and says what
  `--apply` would do. Nothing is written.
- `--apply` prompts per entry: copy / skip. `--apply --all` accepts every
  suggestion for the host-keyed ones and still prompts for bare names.
- **Copy, never move.** The source entry is never deleted or altered, so the
  team repo cannot be broken by a migration run.
- **Idempotent.** An existing destination entry is reported and skipped unless
  `--overwrite` is passed.
- Reuses `_store.sh`'s `read_credential`, `store_credential`, `verify_credential`
  and `list_credentials`, which already abstract macOS `security`, Linux
  `secret-tool`, and the JSON fallback. No new keychain code, and the JSON-store
  case (two `credentials.json` files) falls out for free.
- **Never prints a secret value** — only service names, usernames and outcomes.
- Verifies each write via `verify_credential` before reporting success; a failed
  write is a loud error, not a skipped line.

### Testing

Per-case `HOME` redirection (several scripts write to `~/.claude`, `~/.codex`,
`~/.gemini`, `~/.kiro`). Drive the JSON-fallback backend so cases run without
touching the real keychain, and assert:

1. dry-run writes nothing and classifies host-keyed vs bare-name correctly;
2. `--apply` copies and leaves the source entry intact;
3. re-running is a no-op without `--overwrite`;
4. a destination entry differing from source is preserved unless `--overwrite`;
5. no secret value appears in stdout or stderr;
6. a write that cannot be verified exits non-zero.

For sub-project 1, extend `scripts/tests/test_lib_setup_repo_dir.sh`: two
markers must yield two runtime dirs, each with its own `config.sh`,
`installed.txt` and prefix; an absent marker must still resolve to
`agent-skills-setup`. Assert behavior, never grep for a source line — that
mistake is what let the unguarded `cp` at `install.sh:62` ship.

## Pre-existing issues noted, not fixed here

Flagged because a migration tool touches the same code, and both predate this work:

- `_store.sh:53` passes the secret via `security add-generic-password -w "$pass"`,
  making it visible in `ps` while it runs.
- `_store.sh:61` interpolates `$pass` into a `python3 -c` string, so a password
  containing a quote breaks or injects.

Both should be fixed on their own merits rather than folded into this split.
