#!/usr/bin/env bash
# update.sh — pull latest repo changes and re-install all skills
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_DIR/scripts/_lib.sh"

echo "==> Pulling latest changes..."
git -C "$REPO_DIR" pull --ff-only

echo ""
echo "==> Re-installing skills..."
# Re-run install with same agent selection
bash "$REPO_DIR/scripts/install.sh"
