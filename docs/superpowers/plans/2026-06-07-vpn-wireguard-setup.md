# WireGuard VPN Server Setup Plan

**Date:** 2026-06-07
**Host:** top-EX58-UD3R (`<lan-ip>`)
**Goal:** Secure split-tunnel VPN so 2 laptops + 1 remote host can reach the home LAN.
         Only whitelisted peers can connect. DDNS keeps endpoint current via Cloudflare.

---

## Architecture

```
Internet
    │
    │  vpn.example.com:51820 (UDP)
    │  A record auto-updated by DDNS cron
    │
[Router 192.168.x.254]  ← port-forward UDP 51820 → <lan-ip>
    │
[WireGuard server — wg0 — 10.8.0.1]
    │   192.168.x.0/24 (home LAN reachable through server)
    ├── Laptop 1    10.8.0.2
    ├── Laptop 2    10.8.0.3
    └── Remote host 10.8.0.4
```

**Split tunnel:** clients only route `10.8.0.0/24` and `192.168.x.0/24` through VPN.
All other internet traffic exits normally at each client's local connection.

---

## Security Design

| Layer | Mechanism |
|---|---|
| Peer authentication | WireGuard public/private keypair per peer |
| Extra symmetric layer | Pre-shared key (PSK) per peer — quantum-resistant |
| Peer whitelist | Server config only lists 3 known peers; all others are cryptographically dropped |
| Firewall | UFW: allow UDP 51820 inbound; no other new inbound rules |
| DDNS token | Cloudflare API token scoped to `Zone:DNS:Edit` for `example.com` only |
| Key storage | Private keys in `/etc/wireguard/` (root-only, mode 600) |

---

## Network Details

| Item | Value |
|---|---|
| VPN subnet | `10.8.0.0/24` |
| Server VPN IP | `10.8.0.1` |
| Server LAN IP | `<lan-ip>` |
| WireGuard port | `51820/UDP` |
| Endpoint hostname | `vpn.example.com` |
| DNS provider | Cloudflare |
| Existing subnets (avoid) | `10.42.0.0/16` (k3s pods), `10.43.0.0/16` (k3s svc), `172.17-19.0.0/16` (Docker) |

---

## File Map

| File | Purpose |
|---|---|
| `skills/infra/vpn/IMPL.md` | Skill entry point |
| `skills/infra/vpn/lib/vpn.sh` | Subcommand dispatcher |
| `skills/infra/vpn/lib/setup.sh` | Generate keys, write wg0.conf, UFW rules, enable service |
| `skills/infra/vpn/lib/add-peer.sh` | Add a new peer: generate keys+PSK, print client config + QR |
| `skills/infra/vpn/lib/status.sh` | Show wg show output + peer last-handshake + DDNS current IP |
| `skills/infra/vpn/lib/ddns.sh` | Check public IP vs Cloudflare A record, update if changed |
| `skills/infra/vpn/lib/remove.sh` | Tear down wg0, remove UFW rules, remove cron |
| `/etc/wireguard/wg0.conf` | Server WireGuard config (written by setup.sh) |
| `/etc/wireguard/ddns.env` | Cloudflare token + zone ID + record name (root 600) |
| `/etc/cron.d/wg-ddns` | Runs ddns.sh every 5 min |

---

## Tasks

### Task 1 — Scaffold skill files
- [ ] Create `IMPL.md`, `lib/vpn.sh` dispatcher stubs
- [ ] Create `lib/setup.sh`, `lib/add-peer.sh`, `lib/status.sh`, `lib/ddns.sh`, `lib/remove.sh`

### Task 2 — setup.sh
- [ ] Check `wireguard-tools` installed (already is), install `wireguard` kernel module if missing
- [ ] Generate server keypair → `/etc/wireguard/private.key` (mode 600), `public.key`
- [ ] Write `/etc/wireguard/wg0.conf` with server block (no peers yet)
- [ ] Enable IP forwarding: `net.ipv4.ip_forward=1` in `/etc/sysctl.d/99-wireguard.conf`
- [ ] UFW: allow `51820/udp`, enable UFW masquerade in `/etc/ufw/before.rules`
- [ ] `systemctl enable --now wg-quick@wg0`
- [ ] Print server public key (needed when adding peers from client side)

### Task 3 — add-peer.sh
- [ ] Accept peer name as argument (e.g. `laptop1`)
- [ ] Generate peer keypair + PSK
- [ ] Append `[Peer]` block to `/etc/wireguard/wg0.conf`
- [ ] `wg syncconf wg0` (live reload, no restart needed)
- [ ] Print client `.conf` file content
- [ ] Print QR code via `qrencode` (for mobile/laptop WireGuard app)
- [ ] Save peer public key to `/etc/wireguard/peers/<name>.pub`

### Task 4 — ddns.sh + cron
- [ ] Read Cloudflare token, zone ID, record name from `/etc/wireguard/ddns.env`
- [ ] Get current public IP via `curl -s https://api.ipify.org`
- [ ] Get current A record value via Cloudflare API v4
- [ ] If different: PATCH the record, log to `/var/log/wg-ddns.log`
- [ ] Install `/etc/cron.d/wg-ddns` running every 5 min as root

### Task 5 — status.sh
- [ ] `wg show wg0` (active peers, handshakes, transfer)
- [ ] Current public IP vs current DNS A record value
- [ ] Each peer: name, VPN IP, last handshake age

### Task 6 — Wire into infra SKILL.md + router note
- [ ] Add `/infra-vpn` row to `skills/infra/SKILL.md`
- [ ] Document the one manual step: router port-forward UDP 51820 → <lan-ip>

---

## Prerequisites Before Running setup

1. **Cloudflare API token** — create at dash.cloudflare.com:
   - Permissions: `Zone → DNS → Edit`
   - Zone resources: `example.com` only
2. **Cloudflare Zone ID** — found on the Overview page for example.com in Cloudflare dashboard
3. **Router port-forward** — UDP 51820 → <lan-ip> (manual, router web UI)
4. **`qrencode`** — `sudo apt install qrencode` (for QR code client config output)

## One-time client setup (after server is running)

On each client machine after receiving the generated `.conf` file:
```bash
# Linux client
sudo apt install wireguard-tools
sudo cp <peer>.conf /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0

# macOS / Windows: import .conf into WireGuard app
# Mobile: scan QR code in WireGuard app
```
