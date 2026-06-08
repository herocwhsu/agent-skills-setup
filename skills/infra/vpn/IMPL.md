---
name: infra-vpn
description: WireGuard VPN server on this host. Split-tunnel, 3 whitelisted peers, Cloudflare DDNS. Subcommands: setup, add-peer, status, remove.
---

# infra/vpn

Manage a WireGuard VPN server for secure remote access to the home LAN.

## Subcommands

| Subcommand | What it does |
|---|---|
| `setup` | Generate server keys, write wg0.conf, configure UFW, enable wg-quick@wg0, install DDNS cron |
| `add-peer <name>` | Generate keypair + PSK for a new peer, print client config + QR code |
| `status` | Show active peers, last handshake, public IP vs DNS record |
| `remove` | Tear down wg0, remove UFW rules, remove DDNS cron |

## Invocation

```bash
bash ~/.claude/skills/infra/vpn/lib/vpn.sh <subcommand> [args]
```

## Network design

- VPN subnet: `10.8.0.0/24`
- Server VPN IP: `10.8.0.1`
- Endpoint: configured during `setup` (stored in `/etc/wireguard/ddns.env`)
- Mode: split-tunnel — only `10.8.0.0/24` and the host LAN subnet routed through VPN
- Avoids: `10.42/16` (k3s pods), `10.43/16` (k3s svc), `172.17-19/16` (Docker)

## Security

- Per-peer keypair + pre-shared key (PSK)
- Server whitelists only known peers — unknown peers are cryptographically dropped
- UFW: only UDP 51820 inbound added
- Cloudflare API token stored in `/etc/wireguard/ddns.env` (root-only, mode 600)
- All private keys in `/etc/wireguard/` (root-only, mode 600)

## Prerequisites

Before running `setup`:
1. Cloudflare API token (Zone:DNS:Edit, scoped to your zone only)
2. Cloudflare Zone ID (from Cloudflare dashboard → your domain → Overview)
3. Router: port-forward UDP 51820 → this host's LAN IP (manual step)
4. `sudo apt install qrencode` (for QR code output in add-peer)

## Implementation files

| File | Purpose |
|---|---|
| `lib/vpn.sh` | Subcommand dispatcher |
| `lib/setup.sh` | Server setup: keys, wg0.conf, sysctl, UFW, systemd, DDNS cron |
| `lib/add-peer.sh` | Add peer: keys+PSK, append to wg0.conf, print config+QR |
| `lib/status.sh` | Live peer status + IP/DNS check |
| `lib/ddns.sh` | Cloudflare DDNS updater (runs via cron every 5 min) |
| `lib/remove.sh` | Full teardown |
