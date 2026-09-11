#!/usr/bin/env bash
# update.sh — pull latest repo changes and re-install all skills
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"

SELECTION_FILE="$(skills_runtime_dir "$REPO_DIR")/agent-selection.txt"

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

# A wired hook command embeds an absolute skills path. Reinstalling can move that
# path, leaving the command pointing at nothing -- the hook then stops firing with
# no error anywhere. Refresh what is already wired; opting in is still install.sh's
# --with-hook, so a hook the user never wired stays unwired.
#
# The selection file holds "all" or a comma-separated list, never a shell word
# list, so it is expanded through select_agents rather than word-split. Re-read
# after install.sh because that run may have prompted and rewritten it. Splitting
# it by hand would pass the literal "all" to rewire_hooks, whose case statement
# would return 0 without doing anything -- silent, and the exact failure this step
# exists to prevent.
echo ""
echo "==> Refreshing wired hook paths..."
if [[ -f "$SELECTION_FILE" ]]; then
  select_agents "$(cat "$SELECTION_FILE")"
  for agent in "${SELECTED_AGENTS[@]}"; do
    rewire_hooks "$REPO_DIR" "$agent"
  done
else
  echo "  no saved agent selection; nothing to refresh"
fi
