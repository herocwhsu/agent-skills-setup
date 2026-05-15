#!/usr/bin/env bash
# uninstall.sh — remove superpowers + custom skills for one or more agents
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_DIR/scripts/_lib.sh"

select_agents

# ---------------------------------------------------------------------------
# 1. Remove superpowers
# ---------------------------------------------------------------------------
echo ""
echo "==> Removing superpowers skills..."

for agent in "${SELECTED_AGENTS[@]}"; do
  dir=$(agent_skills_dir "$agent")
  if [[ ! -d "$dir" ]]; then continue; fi

  # Remove each superpowers skill directory (known list from agent-superpowers)
  for skill in brainstorming test-driven-development systematic-debugging \
               writing-plans executing-plans subagent-driven-development \
               requesting-code-review receiving-code-review \
               dispatching-parallel-agents verification-before-completion \
               finishing-a-development-branch using-git-worktrees \
               writing-skills using-superpowers; do
    remove_skill "$skill" "$dir"
  done
  echo "  ✓ superpowers removed from $dir"
done

# Uninstall pip package if present (optional, doesn't affect skill files)
if command -v pip3 &>/dev/null; then
  pip3 uninstall agent-superpowers -y 2>/dev/null || true
elif command -v pip &>/dev/null; then
  pip uninstall agent-superpowers -y 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 2. Remove custom skills from manifest
# ---------------------------------------------------------------------------
echo ""
echo "==> Removing custom skills from manifest..."

while IFS= read -r skill; do
  [[ "$skill" =~ ^#|^[[:space:]]*$ ]] && continue
  for agent in "${SELECTED_AGENTS[@]}"; do
    dir=$(agent_skills_dir "$agent")
    remove_skill "$skill" "$dir"
  done
done < "$REPO_DIR/manifest.txt"

echo ""
echo "Done."
