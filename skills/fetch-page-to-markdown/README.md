# fetch-page-to-markdown

Fetch a Confluence page or any web URL and save it as a dated markdown file in `./docs/pre-specs/`.

## Usage

Just tell your agent the URL:

> "fetch https://confluence.example.com/pages/viewpage.action?spaceKey=PP2&title=My+Page and save as markdown"

The agent will:
1. Detect it's a Confluence URL → use the REST API for clean output
2. Read `$CONFLUENCE_PASS` from your environment (set up via `setup-credentials.sh`)
3. Convert HTML → Markdown (tables, headings, lists preserved)
4. Save to `./docs/pre-specs/YYYY-MM-DD-<page-title>-reference.md`

## Credential Prerequisite

Run once per machine to store your Confluence password in the platform keychain:

**macOS / Linux:**
```bash
bash scripts/setup-credentials.sh
# Choose: 1) Confluence → 1) add
```

**Windows:**
```powershell
.\scripts\setup-credentials.ps1
# Choose: 1) Confluence → 1) add
```

Then restart your shell. The script stores the password in the platform keychain.

To verify (without revealing the value):
```bash
bash scripts/setup-credentials.sh confluence verify
```

## Output Location

```
./docs/pre-specs/2026-05-14-my-page-title-reference.md
```

- Directory is created automatically if it doesn't exist
- Filename: `YYYY-MM-DD-<slug>-reference.md` (slug = title lowercased, max 40 chars)

## Examples

**Confluence page by title:**
> "fetch https://confluence.vivotek.com/pages/viewpage.action?spaceKey=PP2&title=Reseller+Portal+License+naming and save as markdown"

**Any web page (no auth):**
> "fetch https://docs.example.com/api-reference and save as markdown"

**Multiple pages:**
> "fetch these two pages and save both as markdown: [url1] [url2]"

## Non-Confluence URLs

For non-Confluence URLs the agent uses plain `curl` — no auth required unless the site needs it. If the site requires Basic Auth, set the appropriate env var and tell the agent.

## Agent Compatibility

Works with Kiro, Claude Code, GitHub Copilot, and Codex. The `html2md.py` converter is located at install time by scanning `~/.kiro/skills/`, `~/.claude/skills/`, `~/.copilot/skills/`, and `~/.codex/skills/` in order — whichever is found first is used.

## Files

| File | Purpose |
|---|---|
| `SKILL.md` | Agent instructions (read by Kiro/Claude automatically) |
| `html2md.py` | HTML → Markdown converter used at fetch time |
