#!/usr/bin/env bash
# update.sh — pull latest repo changes and re-install all skills
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"

SELECTION_FILE="$(skills_runtime_dir "$REPO_DIR")/agent-selection.txt"

# update.sh means "bring this machine current", so agent CLI updates apply here
# rather than only being reported. --no-update-agents skips them for an offline or
# CI run; the git pull above already needs the network, so this adds no new
# requirement in the normal case.
UPDATE_AGENTS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-update-agents) UPDATE_AGENTS=0; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

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
INSTALL_ARGS=()
[[ -n "$AGENT_ARG" ]] && INSTALL_ARGS+=(--agent "$AGENT_ARG")
# Applied here rather than in a second pass of our own: install.sh already has the
# agent step, and calling update-agents.sh again afterwards enumerated every CLI
# twice -- once reported, once applied -- with the first pass immediately stale.
# An array, not ${VAR:+...}: UPDATE_AGENTS holds 0 or 1, and 0 is non-empty, so
# :+ would expand the flag when it is off.
[[ $UPDATE_AGENTS -eq 1 ]] && INSTALL_ARGS+=(--update-agents)
bash "$REPO_DIR/scripts/install.sh" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}

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
