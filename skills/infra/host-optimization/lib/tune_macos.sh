#!/bin/bash
# Host Optimization - macOS Provider
set -euo pipefail

BACKUP_FILE="$HOME/.agent-skills-setup/backups/host-optimization/macos-defaults.sh"

# ── Backup current values before changing ────────────────────────────────────
backup_macos() {
    mkdir -p "$(dirname "$BACKUP_FILE")"
    local sleep_val hibernatemode_val
    sleep_val=$(pmset -g | awk '/^[[:space:]]+sleep[[:space:]]/{print $2}' | head -1)
    sleep_val=${sleep_val:-1}
    # hibernatemode may not be shown on all hardware — default to 3 (standard safe mode)
    hibernatemode_val=$(pmset -g everything 2>/dev/null | awk '/hibernatemode/{print $2}' | head -1)
    hibernatemode_val=${hibernatemode_val:-3}
    {
        echo "#!/bin/bash"
        echo "# macOS restore script — generated $(date)"
        echo "sudo sysctl -w kern.maxfiles=$(sysctl -n kern.maxfiles)"
        echo "sudo sysctl -w kern.maxfilesperproc=$(sysctl -n kern.maxfilesperproc)"
        echo "sudo pmset -a sleep ${sleep_val}"
        echo "sudo pmset -a hibernatemode ${hibernatemode_val}"
        echo "defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool true"
        echo "defaults write com.apple.dock expose-animation-duration -float 0.5"
        echo "defaults write com.apple.dock launchanim -bool true"
        echo "defaults write com.apple.finder QLInlinePreview -bool true"
    } > "$BACKUP_FILE"
    chmod +x "$BACKUP_FILE"
    echo "[host-opt] Backup written to $BACKUP_FILE (sleep=${sleep_val}, hibernatemode=${hibernatemode_val})"
}

if [[ "${1:-}" == "--revert" ]]; then
    if [[ -f "$BACKUP_FILE" ]]; then
        echo "[host-opt] Reverting macOS settings..."
        bash "$BACKUP_FILE"
        killall Dock || true
        killall Finder || true
        echo "[host-opt] Revert complete."
    else
        echo "[host-opt] No backup found at $BACKUP_FILE — nothing to revert."
        exit 1
    fi
    exit 0
fi

backup_macos

# ── File descriptor limits ────────────────────────────────────────────────────
echo "[host-opt] Setting file descriptor limits..."
sudo sysctl -w kern.maxfiles=524288
sudo sysctl -w kern.maxfilesperproc=524288

# ── Power management ──────────────────────────────────────────────────────────
echo "[host-opt] Configuring power management..."
sudo pmset -a sleep 0
sudo pmset -a hibernatemode 0

# ── Firewall ──────────────────────────────────────────────────────────────────
echo "[host-opt] Enabling application firewall..."
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null || \
    echo "[host-opt] Notice: firewall command requires SIP-allowed context — skipping"

# ── UI Animations ─────────────────────────────────────────────────────────────
echo "[host-opt] Reducing UI animations..."
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
defaults write com.apple.dock expose-animation-duration -float 0.1
defaults write com.apple.dock launchanim -bool false

# ── Finder ────────────────────────────────────────────────────────────────────
echo "[host-opt] Optimizing Finder..."
defaults write com.apple.finder QLInlinePreview -bool false

# ── Restart UI services ───────────────────────────────────────────────────────
echo "[host-opt] Restarting UI services..."
killall Dock || true
killall Finder || true

# ── Memory ────────────────────────────────────────────────────────────────────
echo "[host-opt] Purging inactive memory..."
sudo purge || echo "[host-opt] Notice: purge requires sudo"

echo "[host-opt] macOS tuning complete."

