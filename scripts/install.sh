#!/usr/bin/env bash
# install.sh — install all skills declared in registry.txt
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"

select_agents

echo ""
echo "==> Installing skills from registry.txt..."

for agent in "${SELECTED_AGENTS[@]}"; do
  target_dir=$(agent_skills_dir "$agent")
  echo ""
  echo "  Agent: $agent → $target_dir"

  while IFS=' ' read -r type id subpath_or_empty; do
    # Skip comments and blank lines
    case "$type" in
      ""|\#*) continue ;;
    esac

    case "$type" in
      pip)
        install_pip_skill "$id" "$target_dir" || true
        ;;
      github)
        install_github_skill "$id" "${subpath_or_empty:-.}" "$target_dir" || true
        ;;
      local)
        install_local_skill "$id" "$REPO_DIR" "$target_dir" || true
        ;;
      *)
        echo "  WARNING: unknown type '$type' for '$id', skipping." >&2
        ;;
    esac
  done < "$REPO_DIR/registry.txt"
done

# Install Kiro steering file if kiro was selected
for agent in "${SELECTED_AGENTS[@]}"; do
  if [[ "$agent" == "kiro" ]]; then
    mkdir -p "$HOME/.kiro/prompts"
    for f in "$REPO_DIR/prompts/"*.md; do
      cp "$f" "$HOME/.kiro/prompts/$(basename "$f")"
    done
    echo "  ✓ kiro prompts → ~/.kiro/prompts/"
    break
  fi
done

echo ""
echo "Done. Run scripts/setup-credentials.sh to configure service credentials."
