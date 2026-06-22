---
name: infra
description: Use to manage local infrastructure that supports Claude Code and Kiro IDE workflows. Subcommands manage the kiro-gateway Docker proxy (kiro-gateway), run host-level performance/security tuning (host-optimization), set up the Apidog MCP server (apidog-mcp), and configure tmux clipboard integration (tmux-yank). Not part of the spec-gated workflow — these run independently.
---

# infra

Local-machine infrastructure tooling. Sits outside the spec-gated workflow
because these subcommands manage the agent's own runtime environment, not a
target product repo.

## Subcommands

| Slash command | What it does | Implementation |
|---|---|---|
| `/infra-kiro-gateway <subcommand>` | Manage the kiro-gateway Docker container. Sub-subcommands: `init`, `update`, `rollback`, `status`, `setup-alias`. Pins digest on first run. | `kiro-gateway/IMPL.md` |
| `/infra-host-optimization` | Run host CPU / GPU / RAM / network tuning. Has a `--revert` flag to undo. macOS + Linux. | `host-optimization/IMPL.md` |
| `/infra-ups <subcommand>` | Manage UPS power protection via NUT. Sub-subcommands: `setup`, `status`, `battery-health`, `battery-replace`, `test-shutdown`, `remove`. Triggers graceful shutdown after 60 s on battery. | `ups/IMPL.md` |
| `/infra-vpn <subcommand>` | WireGuard VPN server. Split-tunnel, 3 whitelisted peers, Cloudflare DDNS. Sub-subcommands: `setup`, `add-peer <name>`, `status`, `remove`. | `vpn/IMPL.md` |
| `/infra-apidog-mcp <subcommand>` | Install and configure `@lstpsche/apidog-mcp` MCP server. Sub-subcommands: `setup`, `status`, `remove`. Wires Apidog token from keychain into agent settings. | `apidog-mcp/IMPL.md` |
| `/infra-tmux-yank` | Install tmux + TPM + tmux-yank for system clipboard integration. macOS (pbcopy), Linux X11 (xclip), Wayland (wl-copy), SSH (OSC 52). | `tmux-yank/IMPL.md` |

## When to use which subcommand

```
Need Claude Code or Kiro IDE to authenticate via AWS/Kiro creds → /infra-kiro-gateway init
Container running an old image → /infra-kiro-gateway update
Update broke something → /infra-kiro-gateway rollback
Want to check current image digest / state → /infra-kiro-gateway status
Machine feels slow, want tuning sweep → /infra-host-optimization
Tuning made things worse → /infra-host-optimization --revert
Need to set up Apidog MCP for agent workflow → /infra-apidog-mcp setup
Need tmux clipboard to work in macOS/Linux/SSH → /infra-tmux-yank
```

## State files

| Subcommand | State location |
|---|---|
| `kiro-gateway` | `~/.agent-skills-setup/kiro-gateway.state` (current/previous digest) |
| `host-optimization` | `~/.agent-skills-setup/backups/host-optimization/` |

## Migration note

| Old skill | New subcommand | Old slash | New slash |
|---|---|---|---|
| `kiro-gateway` | `infra/kiro-gateway` | `/kiro-gateway` | `/infra-kiro-gateway` |
| `host-optimization` | `infra/host-optimization` | `/host-optimization` | `/infra-host-optimization` |

`infra/kiro-gateway/IMPL.md` updated to reference the new install path
(`~/.claude/skills/infra/kiro-gateway/lib/kiro-gateway.sh`). Same scripts,
same state file, same behavior.
