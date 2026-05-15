# agent-skills-setup

One-command setup for [Agent Skills](https://agentskills.io) across multiple AI agents and platforms.

Installs:
- **[superpowers](https://github.com/obra/superpowers)** — brainstorming, TDD, systematic debugging, code review, and more
- **Custom skills** — fetch-page-to-markdown (Confluence + any web page → markdown)

Supports: Kiro, Claude Code, GitHub Copilot, Codex · macOS, Linux, Windows

---

## Quick Start

```bash
git clone https://github.com/herocwhsu/agent-skills-setup
cd agent-skills-setup
bash scripts/install.sh          # installs superpowers + custom skills
bash scripts/setup-credentials.sh  # store Confluence credentials in keychain
```

Restart your shell after setup.

---

## Scripts

| Script | What it does |
|---|---|
| `scripts/install.sh` | Install superpowers + custom skills. Prompts for target agent(s). |
| `scripts/uninstall.sh` | Remove installed skills. Only touches skills from this repo. |
| `scripts/update.sh` | `git pull` + re-install. |
| `scripts/setup-credentials.sh` | Store Confluence credentials in platform keychain. |

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

`setup-credentials.sh` stores your Confluence password in the platform keychain and adds an export block to your shell profile so `$CONFLUENCE_PASS` is always available.

| Platform | Storage |
|---|---|
| macOS | Keychain (`security`) |
| Linux (GUI) | GNOME Keyring (`secret-tool`) |
| Linux (headless/CI) | Inject `CONFLUENCE_PASS` via pipeline secret |
| Windows | Credential Manager (`cmdkey`) |

---

## Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` (and any supporting files)
2. Add `<skill-name>` to `manifest.txt`
3. Run `bash scripts/install.sh` to deploy

The install script only manages skills listed in `manifest.txt` — all other skills in your agent's skills directory are left untouched.

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
