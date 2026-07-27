# kiro-gateway

Manages the kiro-gateway Docker container: builds a SHA-tagged image locally from a fork checkout, with rollback.

## Requirements

- Docker installed and running
- git, and SSH access to `git@github.com:herocwhsu/kiro-gateway.git` (the fork `init` clones)
- Kiro CLI run at least once (creates the data dir the container mounts)

## Install

```bash
bash scripts/install.sh
```

Adds `~/.claude/skills/infra/kiro-gateway/` (and `~/.kiro/skills/infra/kiro-gateway/` if kiro is selected) as a symlink into this repo.

After installing, set up the `claude-kiro` shell alias:

```bash
bash ~/.claude/skills/infra/kiro-gateway/lib/kiro-gateway.sh setup-alias
source ~/.zshrc  # or ~/.bash_profile / ~/.bashrc
```

This stores the proxy key in your system keychain and adds the `claude-kiro` alias to your shell rc file. The alias reads the key from keychain at runtime — no plaintext token is written to any file. Once sourced, launch Claude Code through the gateway with:

```bash
claude-kiro
```

## Usage

Tell your AI agent: "set up kiro-gateway" / "update kiro-gateway" / "rollback kiro-gateway" / "kiro-gateway status" / "set up claude-kiro alias".

Or run directly:

```bash
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh init
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh update
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh rollback
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh status
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh setup-alias
```

## The claude-kiro alias

`claude-kiro` is a shell alias that launches Claude Code with the gateway as its backend. The proxy key is read from keychain at runtime:

```bash
alias claude-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ANTHROPIC_API_KEY=$(security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w 2>/dev/null) claude'
```

On Linux, `secret-tool` is used instead of `security`. On headless Linux, the key falls back to `$KIRO_PROXY_KEY` set in `~/.zshrc.local`.

**Workflow:**
1. `bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh init` — start the container
2. `claude-kiro` — launch Claude Code through the gateway

## The codex-kiro alias

`codex-kiro` launches OpenAI's Codex CLI against the gateway using an isolated
config home so it never collides with anything already in `~/.codex`:

```bash
alias codex-kiro='CODEX_HOME="$HOME/.codex-kiro" KIRO_PROXY_KEY=$(security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w 2>/dev/null) codex --profile kiro'
```

Set it up with:

```bash
bash ~/.claude/skills/infra/kiro-gateway/lib/kiro-gateway.sh setup-codex
source ~/.zshrc
```

This writes `~/.codex-kiro/config.toml`:

```toml
[model_providers.kiro]
name = "Kiro Gateway"
base_url = "http://localhost:7788/v1"
env_key = "KIRO_PROXY_KEY"
wire_api = "chat"

[profiles.kiro]
model = "claude-opus-4.8"
model_provider = "kiro"
```

`wire_api = "chat"` is required — the gateway serves OpenAI Chat Completions,
not the Responses API. Override the model per run: `codex-kiro -m claude-sonnet-4.6`.

If `codex` isn't installed, `setup-codex` still writes the config and prints
`npm i -g @openai/codex`. Remove everything with `remove-codex`.

Smoke test once installed:

```bash
codex-kiro exec "reply with OK"
```

## Container details

| Setting | Value |
|---|---|
| Image | `kiro-gateway:<sha>` — built locally from the fork, SHA-tagged |
| Host port | `127.0.0.1:7788` |
| Container port | `8000` |
| Volume | `<kiro-data-dir> → /home/kiro/.local/share/kiro-cli` (read-only) |
| Restart | `unless-stopped` |

Data dir by platform:
- macOS: `$HOME/Library/Application Support/kiro-cli`
- Linux: `$HOME/.local/share/kiro-cli`

## State file

`~/.agent-skills-setup/kiro-gateway.state`

Tracks current and previous image SHAs for rollback. Never delete this file manually — use `rollback` instead.

## Build path

`init` clones the fork (`git@github.com:herocwhsu/kiro-gateway.git`) into
`~/.agent-skills-setup/kiro-gateway` on first run. To reuse an existing local
checkout instead, set `KIRO_GATEWAY_DIR=/path/to/checkout` — it's symlinked in
rather than cloned. Before every build, `fix_guard` asserts the `role: str`
field is present in `kiro/models_anthropic.py`, applying the tracked patch
(`patches/kiro-gateway-system-role.patch`) if not, and aborting if the patch
won't apply cleanly. After a successful `init`/`update`, an HTTP health probe
sends a system-role request and expects a 200 response. `status` reports the
build path (linked vs. cloned) and the current image tag.

## Troubleshooting

**"claude-kiro: command not found"** — Run `setup-alias` then `source` your rc file. Or start a new shell.

**"kiro data dir not found"** — Run Kiro IDE or CLI once to create it, then retry `init`.

**"docker: command not found"** — Install Docker Desktop (macOS) or `docker-ce` (Linux).

**"no previous version recorded"** — `rollback` requires at least one prior `update`. There is no version before the first SHA-tagged build.
