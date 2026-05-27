#!/usr/bin/env bash
# install.sh — install all skills declared in registry.txt
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"

AGENT_ARG=""
HOOK_SKILLS=()
WITH_AGENTS_MD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      AGENT_ARG="$2"; shift 2 ;;
    --agent=*)
      AGENT_ARG="${1#*=}"; shift ;;
    --with-hook)
      HOOK_SKILLS+=("$2"); shift 2 ;;
    --with-hook=*)
      HOOK_SKILLS+=("${1#*=}"); shift ;;
    --with-agents-md)
      WITH_AGENTS_MD=1; shift ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

select_agents "$AGENT_ARG"

echo ""
echo "==> Installing runtime helpers..."
install_runtime_dir "$REPO_DIR"

echo ""
echo "==> Migrating keychain entries (if any)..."
# shellcheck source=/dev/null
source "$HOME/.agent-skills-setup/lib.sh"
migrate_keychain

INSTALLED_LIST="$HOME/.agent-skills-setup/installed.txt"
> "$INSTALLED_LIST"  # truncate

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

# Install Kiro prompts if kiro was selected
for agent in "${SELECTED_AGENTS[@]}"; do
  if [[ "$agent" == "kiro" ]]; then
    install_kiro_prompts "$REPO_DIR"
    break
  fi
done

if [[ ${#HOOK_SKILLS[@]} -gt 0 ]]; then
  echo ""
  echo "==> Wiring hooks..."
  for skill in "${HOOK_SKILLS[@]}"; do
    wire_hook "$skill" "$REPO_DIR"
  done
fi

if [[ $WITH_AGENTS_MD -eq 1 ]]; then
  echo ""
  echo "==> Deploying always-on engineering rules..."
  bash "$REPO_DIR/scripts/install-agents-md.sh"
fi

echo ""
echo "Done. Run scripts/setup-credentials.sh to configure service credentials."
