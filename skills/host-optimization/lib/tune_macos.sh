#!/bin/bash
# Host Optimization - macOS Provider
set -euo pipefail

echo "Optimizing UI Animations..."
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
defaults write com.apple.dock expose-animation-duration -float 0.1
defaults write com.apple.dock launchanim -bool false

echo "Optimizing Finder and Dock..."
defaults write com.apple.finder QLInlinePreview -bool false

echo "Restarting UI Services..."
killall Dock || true
killall Finder || true

echo "Purging inactive memory..."
sudo purge || echo "Notice: sudo purge might require root privileges"

echo "macOS tuning complete."
