#!/usr/bin/env bash
set -euo pipefail

read -rp "  Remove WireGuard VPN entirely? This deletes all keys and configs. [y/N] " ans
[[ "${ans,,}" == "y" ]] || { echo "Aborted."; exit 0; }

sudo systemctl disable --now wg-quick@wg0 2>/dev/null || true
sudo ufw delete allow 51820/udp 2>/dev/null || true
sudo rm -f /etc/cron.d/wg-ddns
sudo rm -f /etc/sysctl.d/99-wireguard.conf
sudo sysctl --system > /dev/null 2>&1

echo "Keys and configs preserved at /etc/wireguard/ — remove manually if desired:"
echo "  sudo rm -rf /etc/wireguard/"
echo ""
echo "Done. WireGuard service stopped, UFW rule removed, DDNS cron removed."
