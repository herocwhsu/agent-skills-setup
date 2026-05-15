# agent-skills-setup

One-command setup for [Agent Skills](https://agentskills.io) across multiple AI agents and platforms.

Installs:
- **[superpowers](https://github.com/obra/superpowers)** — brainstorming, TDD, systematic debugging, code review, and more
- **Custom skills** — fetch-page-to-markdown (Confluence + any web page → markdown)

Supports: Kiro, Claude Code, GitHub Copilot, Codex · macOS, Linux, Windows

---

## Quick Start

**macOS / Linux / Git Bash:**
```bash
git clone https://github.com/herocwhsu/agent-skills-setup
cd agent-skills-setup
bash scripts/install.sh
bash scripts/setup-credentials.sh
```

**Windows 11 (native PowerShell):**
```powershell
git clone https://github.com/herocwhsu/agent-skills-setup
cd agent-skills-setup
.\scripts\install.ps1
.\scripts\setup-credentials.ps1
```

Restart your shell after setup.

---

## Scripts

| Script | Platform | What it does |
|---|---|---|
| `scripts/install.sh` | macOS / Linux / Git Bash | Install superpowers + custom skills |
| `scripts/install.ps1` | Windows PowerShell | Same, native Windows |
| `scripts/uninstall.sh` | macOS / Linux / Git Bash | Remove installed skills |
| `scripts/update.sh` | macOS / Linux / Git Bash | `git pull` + re-install |
| `scripts/setup-credentials.sh` | macOS / Linux / Git Bash | Store service credentials in keychain |
| `scripts/setup-credentials.ps1` | Windows PowerShell | Same, via Windows Credential Manager |

---

## Supported Agents

When prompted, choose one or more:

| # | Agent | Skills directory |
|---|---|---|
| 1 | Kiro | `~/.kiro/skills/` |
| 2 | Claude Code | `~/.claude/skills/` |
| 3 | GitHub Copilot | `~/.copilot/skills/` |
| 4 | Codex | `~/.codex/skills/` |
| 5 | All | all of the above |

---

## Credential Setup

`setup-credentials.sh` (bash) and `setup-credentials.ps1` (PowerShell) manage credentials for multiple services. Passwords are stored in the platform keychain only — **never exported to env vars**.

**Supported services:**

| Service | Used by |
|---|---|
| Confluence | `fetch-page-to-markdown` skill |
| Jira | future Jira skills |
| Apidog | future Apidog skills |

**Actions:** `add` · `update` · `delete` · `list` · `verify`

**Verify a credential is stored (safe — value never printed):**
```bash
bash scripts/setup-credentials.sh confluence verify
```

**Platform storage:**

| Platform | Storage | Script |
|---|---|---|
| macOS | Keychain (`security`) | `setup-credentials.sh` |
| Linux (GUI) | GNOME Keyring (`secret-tool`) | `setup-credentials.sh` |
| Linux (headless/CI) | Inject via pipeline secret at use-time | — |
| Windows 11 | Credential Manager (`CredentialManager` PS module) | `setup-credentials.ps1` |

All entries are namespaced `agent-skills:<service>` to avoid collisions with system or browser keychain entries.

**Windows note:** `setup-credentials.ps1` auto-installs the [`CredentialManager`](https://www.powershellgallery.com/packages/CredentialManager) module from PSGallery on first run.

---

## Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` (and any supporting files)
2. Add `local  <skill-name>` to `registry.txt`
3. Run `bash scripts/install.sh` (or `.\scripts\install.ps1` on Windows) to deploy

The install script only manages skills listed in `registry.txt` — all other skills in your agent's skills directory are left untouched.

---

## Custom Skills

### fetch-page-to-markdown

Fetch Confluence pages or any web URL and save as a dated markdown reference file.

- Confluence REST API path for clean structured output
- Plain `curl` fallback for any non-Confluence URL
- Multi-platform credential storage via keychain
- Bundled `html2md.py` converter handles tables, headings, lists, code blocks

See [`skills/fetch-page-to-markdown/SKILL.md`](skills/fetch-page-to-markdown/SKILL.md) for full usage.

---

## Requirements

The install script needs only `bash` + one of `curl`/`wget`. Python 3 is required only for `html2md.py` at fetch time (not at install time).

`pip` is used to install superpowers if available; otherwise the script falls back to downloading directly from GitHub — no pip required.
