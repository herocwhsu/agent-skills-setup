---
title: codex-kiro gateway integration
date: 2026-07-23
status: draft
---

# codex-kiro gateway integration

Extend the `kiro-gateway` skill so OpenAI's Codex CLI can talk to the existing
kiro-gateway container, mirroring the `claude-kiro` / `hermes-kiro` setup that
already routes Claude Code and Hermes through the gateway.

## Problem

`kiro-gateway.sh setup-alias` wires Claude Code (`claude-kiro`) and Hermes
(`hermes-kiro`) to the gateway via env-var aliases that read the proxy key from
keychain at runtime. Codex CLI has no equivalent. Unlike the other two tools,
Codex cannot be configured by an alias alone — it needs a `config.toml` provider
block, and it defaults to the OpenAI Responses wire protocol, which the gateway
does not serve. There is currently no one-command way to configure it.

## Goals

- One-command `setup-codex` that configures Codex CLI to use the gateway
- Reuse the existing keychain proxy-key logic from `setup-alias`
- Keep Codex config fully isolated from the unrelated tool already occupying `~/.codex`
- `remove-codex` teardown and `status` visibility for symmetry with the rest of the skill
- Fit the existing skill structure (single `kiro-gateway.sh`, bash test file)

## Non-Goals

- Installing Codex CLI (`npm i -g @openai/codex`) — the skill checks for the
  binary and prints the install command, but does not install it
- Patching the gateway image — model IDs pass straight through to Kiro; no local
  patch is needed (see Findings)
- Supporting the OpenAI Responses wire protocol — the gateway only serves Chat
  Completions; `wire_api = "chat"` is mandatory
- fable-5 support — the gateway backend returns HTTP 400 for it (backend /
  subscription limitation, not a gateway ID-mapping gap)

## Findings (verified against the running gateway)

Probed the live container at `127.0.0.1:7788`:

| Endpoint | Result | Meaning |
|---|---|---|
| `POST /v1/chat/completions` | 200 with key | OpenAI Chat Completions served |
| `GET /v1/models` | 200, **stale list** | model list is hardcoded/stale, not authoritative |
| `POST /v1/responses` | 404 | OpenAI Responses **not** served |
| `POST /v1/messages` | 401/200 | Anthropic format (used by `claude-kiro`) |

Model IDs pass straight through to the Kiro backend — the `/v1/models` list is
not authoritative. Direct inference probes:

| Model sent | HTTP | Notes |
|---|---|---|
| `claude-opus-4.8` | 200 | works, though **not** in `/v1/models` |
| `claude-opus-4-8` | 200 | dash variant also works |
| `claude-opus-4.7` | 200 | works |
| `claude-fable-5` / `fable-5` | 400 | "Invalid model ID or insufficient subscription level" |
| garbage id | 400 | same error as fable-5 |

Because opus-4.8 (unlisted) succeeds while fable-5 fails with the same error as a
nonsense ID, the rejection originates in the Kiro backend, not in gateway ID
mapping. A gateway code patch would not fix fable-5.

## Design

### New subcommands

Three additions to `kiro-gateway.sh`, dispatched like the existing subcommands:

| Subcommand | What it does |
|---|---|
| `setup-codex` | Ensure proxy key in keychain, write `~/.codex-kiro/config.toml`, append `codex-kiro` alias, check for `codex` binary. Idempotent. |
| `remove-codex` | Remove the `codex-kiro` alias line and the `~/.codex-kiro` dir. |
| `status` (extended) | Add one line: whether the codex-kiro profile + alias are configured. |

### `setup-codex` steps (in order)

1. **Ensure proxy key in keychain.** Reuse the exact keychain logic from
   `setup-alias` (`agent-skills-setup:kiro-gateway` / `proxy-key`). Same
   fallbacks: prompt (default `kiro-local`), Linux `secret-tool`, headless
   `~/.zshrc.local` with `KIRO_PROXY_KEY`.
2. **Write `~/.codex-kiro/config.toml`.** Fresh file we fully own (isolated
   `CODEX_HOME`). Idempotent: skip if `[model_providers.kiro]` already present.
3. **Append the `codex-kiro` alias** to the rc file. Idempotent: skip if
   `codex-kiro` already present.
4. **Check for `codex` binary.** Config and alias are written regardless. If
   `command -v codex` fails, print the install command
   (`npm i -g @openai/codex`) as a closing notice and exit 0.

Writing config even when `codex` is absent means the setup is ready the moment
the user installs Codex — no re-run required.

### Config file: `~/.codex-kiro/config.toml`

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

- `wire_api = "chat"` is **mandatory** — the gateway 404s on `/v1/responses`, so
  Codex's default Responses protocol would fail outright.
- `env_key = "KIRO_PROXY_KEY"` — Codex reads the key from that env var, supplied
  by the alias at runtime.
- Default model `claude-opus-4.8` (confirmed working via passthrough).
  Overridable per-invocation: `codex-kiro -m claude-sonnet-4.6`.

### The alias

```bash
alias codex-kiro='CODEX_HOME="$HOME/.codex-kiro" KIRO_PROXY_KEY=$(security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w 2>/dev/null) codex --profile kiro'
```

Same keychain-at-runtime pattern as `claude-kiro` / `hermes-kiro` — no plaintext
token in any file. Linux uses `secret-tool`; headless falls back to
`$KIRO_PROXY_KEY`. `CODEX_HOME` points Codex at the isolated config dir.

### Isolation rationale

The existing `~/.codex/config.toml` is occupied by a **different tool**
(`[marketplaces.*]` / `[plugins.*]` tables). Rather than back up and merge our
tables into a foreign file — risking breakage in either direction — we set
`CODEX_HOME=~/.codex-kiro` so this Codex reads a config we fully own. Supported
by Codex CLI (`CODEX_HOME` is honored), no merge logic, no coexistence risk.

Trade-off: `codex-kiro` does not share session/history with whatever lives in
`~/.codex`. That is intended — they are different tools.

## Testing

Extend `tests/test_kiro_gateway.sh`. Mock `security` and a fake `codex` on PATH;
point `HOME` / rc file / `CODEX_HOME` at temp dirs. Assert:

- `setup-codex` writes `config.toml` with the correct provider + profile block,
  including `wire_api = "chat"` and `model = "claude-opus-4.8"`
- the `codex-kiro` alias is appended to the rc file
- re-running `setup-codex` is idempotent (no duplicate block, no duplicate alias)
- missing-`codex` path still writes config and prints the install hint, exit 0
- `remove-codex` removes the alias line and the `~/.codex-kiro` dir
- `status` reports codex-kiro configured / not configured

## Documentation

Update `kiro-gateway/IMPL.md`, `kiro-gateway/README.md`, and the parent
`infra/SKILL.md` subcommand table to describe `setup-codex` / `remove-codex` and
the `codex-kiro` alias.

## Manual smoke test (post-install, documented not automated)

Codex is not currently installed, so end-to-end cannot be verified now. Once
installed:

```bash
codex-kiro exec "reply with OK"   # expect a response routed through the gateway
```

## Known Limitations

- fable-5 returns HTTP 400 through the gateway (backend / subscription, not a
  gateway patch). Out of scope.
- The gateway `/v1/models` list is stale and not authoritative; served models
  are whatever the Kiro backend accepts. Default is pinned to a
  confirmed-working ID rather than derived from the list.
