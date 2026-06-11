#!/usr/bin/env bash
# update.sh — pull latest repo changes and re-install all skills
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"

SELECTION_FILE="$HOME/.agent-skills-setup/agent-selection.txt"

echo "==> Pulling latest changes..."
if ! git -C "$REPO_DIR" pull --ff-only; then
  echo ""
  echo "ERROR: git pull failed (possible diverged branch or network issue)." >&2
  echo "  Fix the git state manually, then re-run: bash scripts/update.sh" >&2
  exit 1
fi

# Read previously saved agent selection
AGENT_ARG=""
if [[ -f "$SELECTION_FILE" ]]; then
  AGENT_ARG=$(cat "$SELECTION_FILE")
  echo ""
  echo "==> Using saved agent selection: $AGENT_ARG"
fi

echo ""
echo "==> Re-installing skills..."
bash "$REPO_DIR/scripts/install.sh" ${AGENT_ARG:+--agent "$AGENT_ARG"}
