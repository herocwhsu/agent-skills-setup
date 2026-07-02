# External Skills & Plugins Integration Plan

> **Status:** APPROVED SCOPE (2026-07-02) — decisions resolved, ready for task-level breakdown (`/writing-plans`).
> Decisions: claude-hud replaces the current statusline · claude-mem **deferred** (backlogged) · Linear via `wrsmith108/linear-claude-skill` · Google Workspace skills **dropped** (no Workspace account).

**Goal:** Refactor the registry/installer so it can consume external Claude Code **plugins** and **single skills from multi-skill repos**, then onboard six requested sources: claude-hud, trailofbits/skills, anthropics webapp-testing, anthropics knowledge-work-plugins (productivity + product-management), Linear/Kanban/Google-Workspace skills from awesome-claude-skills, and claude-mem.

---

## Investigation Findings

### What each source actually is

| Source | Type | Install path today | Fits current registry? |
|---|---|---|---|
| `jarrodwatts/claude-hud` | Claude Code **plugin** (statusline HUD: context usage, tools, agents, todos) | `/plugin marketplace add` + `/plugin install`; Node 18+ | ❌ no `plugin` type |
| `trailofbits/skills` | Plugin **marketplace**, ~40 security plugins under `plugins/` | marketplace | ❌ no `plugin` type |
| `anthropics/skills` → webapp-testing | Plain skill at `skills/webapp-testing/` | zip download works | ⚠️ `github … skills` would install ALL skills (docx, pdf, pptx, xlsx…) |
| `anthropics/knowledge-work-plugins` → productivity, product-management | **Plugins** (commands + skills + `.mcp.json` connectors: Slack, Linear, Jira, Notion, Figma…) | marketplace / `claude plugin install` | ❌ no `plugin` type |
| `mattjoyce/kanban-skill` | Skill at `skills/kanban-ai/` (file-based markdown kanban, zero deps) | zip download | ✅ `github mattjoyce/kanban-skill skills` works as-is |
| `wrsmith108/linear-claude-skill` | Skill with `SKILL.md` at **repo root**; needs Linear MCP or API key | zip download | ❌ installer expects skills as subdirs of subpath |
| `sanjay3290/ai-skills` → Google Workspace | 7 skills (`gmail`, `google-calendar`, `google-docs`, `google-sheets`, `google-slides`, `google-drive`, `google-chat`) under `skills/`, next to unrelated ones (postgres, mysql, imagen…) | zip download | ⚠️ subpath install would drag in all non-Google skills too |
| `thedotmack/claude-mem` | Hook-based **memory system**: 5 lifecycle hooks + worker service on :37777 + SQLite + Chroma vector DB; Node 20+, Bun, uv | `npx claude-mem install` or plugin marketplace | ❌ it's a service, not a skill |

### Gaps in current infrastructure

1. **No `plugin` registry type.** 4 of 6 sources are Claude Code plugins (commands + MCP + hooks bundled). Plugins are Claude-Code-only — Kiro/Gemini can't consume them, so the installer must apply them only for the `claude` agent.
2. **No single-skill selection from GitHub repos.** `install_github_skill` (scripts/_lib.sh:196) copies *every* directory under the subpath. Blocks webapp-testing (sibling of docx/pdf/…), Google Workspace picks (siblings of postgres/mysql/…), and root-level skills (linear-claude-skill).
3. **Conflicts to resolve:**
   - claude-hud **replaces the statusline** that `setup-host.sh` installs (`config/statusline-command.sh` with the `[ctx: Xk/Yk]` display). Both can't own the statusline.
   - claude-mem **overlaps the built-in Claude Code auto-memory** (MEMORY.md per project). Running both means two memory systems writing in parallel.
   - Google Workspace skills state **"Personal Gmail accounts are not supported"** — the account in use (`firstdigital.top@gmail.com`) is personal Gmail unless a Workspace account exists. Verify before investing setup time.

---

## Plan

### Phase 1 — Installer refactor (prerequisite) — ✅ DONE 2026-07-02

| Action | Path | Responsibility |
|---|---|---|
| Modify | `registry.txt` header + `scripts/validate-registry.sh` | Two new types (below) |
| Modify | `scripts/_lib.sh` | `install_github_single_skill`, `install_claude_plugin` |
| Modify | `scripts/install.sh`, `scripts/uninstall.sh`, `scripts/update.sh` | Dispatch new types; plugins only for `claude` agent (warn+skip for kiro/gemini) |
| Modify | `scripts/install.ps1` | Same, or document as bash-only for new types |
| Create | `scripts/tests/test_registry_types.sh` | Cover both new types |
| Modify | `README.md` | Registry format docs |

New registry types:

```
# Install exactly one skill dir (last path component = skill name; "." = repo root)
github-skill  anthropics/skills            skills/webapp-testing
github-skill  wrsmith108/linear-claude-skill  .  linear

# Claude Code plugin via marketplace (claude agent only)
plugin  jarrodwatts/claude-hud                claude-hud
plugin  anthropics/knowledge-work-plugins     productivity
```

`install_claude_plugin` shells out to `claude plugin marketplace add <repo>` (idempotent) then `claude plugin install <name>@<marketplace>`; skipped with a warning when `claude` CLI is absent or agent ≠ claude.

### Phase 2 — Registry entries — ✅ DONE 2026-07-02

> As-built deltas: trailofbits marketplace name is `trailofbits` (not the repo name) so those entries carry an explicit marketplace field; there is no `semgrep` plugin — substituted `static-analysis` (the closest match; `semgrep-rule-creator`/`-variant-creator` also exist). kanban-skill's default branch is `master`, so installers now download `archive/HEAD.zip` (resolves any default branch) instead of hardcoding `main`.

```
github-skill  anthropics/skills               skills/webapp-testing
github        mattjoyce/kanban-skill          skills
github-skill  wrsmith108/linear-claude-skill  .  linear
plugin        jarrodwatts/claude-hud             claude-hud
plugin        anthropics/knowledge-work-plugins  productivity
plugin        anthropics/knowledge-work-plugins  product-management
plugin        trailofbits/skills                 differential-review
plugin        trailofbits/skills                 property-based-testing
plugin        trailofbits/skills                 semgrep
# trailofbits marketplace add makes the other ~37 plugins browsable via /plugin menu
```

### Phase 3 — Host/setup integration — ✅ DONE 2026-07-02

> As-built: setup-host.sh generates the claude-hud statusLine command itself (same template as /claude-hud:setup — runtime detection bun>node, version-sorted plugin path, COLUMNS export), so no interactive setup step is needed. Also fixed setup-credentials.sh dispatch, which pointed at per-service scripts (`credentials/<service>.sh`) that no longer exist — now falls through to the generic `service.sh`.

- `setup-host.sh`: claude-hud becomes the statusline — the plugin install (Phase 2) owns it; remove/skip the script's own statusline block, keeping a `--legacy-statusline` escape hatch for hosts without Node 18+.
- claude-mem: **deferred** — tracked in `docs/backlog.md`; revisit after evaluating whether built-in auto-memory falls short on long projects.
- Credentials: Linear API key → extend `setup-credentials.sh` (`linear` service, keychain-namespaced like the others).

### Phase 4 — Docs & verification

- README: new sources table, conflict notes (statusline, memory).
- Run `bash scripts/install.sh --agent claude` + `scripts/run-tests.sh`; verify each skill/plugin appears (`ls ~/.claude/skills/`, `claude plugin list`).

---

## Resolved Decisions (2026-07-02)

1. **Statusline** → claude-hud replaces the current `[ctx: Xk/Yk]` script.
2. **claude-mem** → deferred to backlog; built-in auto-memory stays the only memory system for now.
3. **Linear** → in scope, `wrsmith108/linear-claude-skill` (MCP + SDK + GraphQL fallback); `Valian/linear-cli-skill` skipped.
4. **Google Workspace skills** → dropped — no Workspace account (personal Gmail unsupported by those skills). Revisit if a Workspace account is created.
5. **trailofbits starting set** → `differential-review`, `property-based-testing`, `semgrep`; the rest stay browsable via `/plugin menu` once the marketplace is added.
