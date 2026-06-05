#!/usr/bin/env bash
# uninstall.sh — remove all skills declared in registry.txt
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"

AGENT_ARG=""
HOOK_SKILLS=()
WITH_AGENTS_MD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)    AGENT_ARG="$2"; shift 2 ;;
    --agent=*)  AGENT_ARG="${1#*=}"; shift ;;
    --with-hook)    HOOK_SKILLS+=("$2"); shift 2 ;;
    --with-hook=*)  HOOK_SKILLS+=("${1#*=}"); shift ;;
    --with-agents-md) WITH_AGENTS_MD=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

select_agents "$AGENT_ARG"

echo ""
echo "==> Removing global packages..."
while IFS=' ' read -r type id subpath_or_empty; do
  case "$type" in ""|\#*) continue ;; esac
  case "$type" in
    npm) uninstall_npm_skill "$id" || true ;;
    pip) uninstall_pip_skill "$id" || true ;;
  esac
done < "$REPO_DIR/registry.txt"

echo ""
echo "==> Removing per-agent skills from registry.txt..."

for agent in "${SELECTED_AGENTS[@]}"; do
  target_dir=$(agent_skills_dir "$agent")
  echo ""
  echo "  Agent: $agent → $target_dir"

  # Kiro also removes prompt files
  if [[ "$agent" == "kiro" ]]; then
    uninstall_kiro_prompts "$REPO_DIR"
  fi

  while IFS=' ' read -r type id subpath_or_empty; do
    case "$type" in
      ""|\#*) continue ;;
    esac

    case "$type" in
      pip|npm)
        # Already handled in the global pass above
        ;;
      github)
        uninstall_github_skill "$id" "${subpath_or_empty:-.}" "$target_dir" || true
        ;;
      local)
        uninstall_local_skill "$id" "$target_dir" || true
        ;;
      local-optional)
        uninstall_local_optional_skill "$id" "$target_dir" || true
        ;;
      *)
        echo "  WARNING: unknown type '$type' for '$id', skipping." >&2
        ;;
    esac
  done < "$REPO_DIR/registry.txt"
done

if [[ ${#HOOK_SKILLS[@]} -gt 0 ]]; then
  echo ""
  echo "==> Un-wiring hooks..."
  for skill in "${HOOK_SKILLS[@]}"; do
    for agent in "${SELECTED_AGENTS[@]}"; do
      unwire_hook "$skill" "$REPO_DIR" "$agent"
    done
  done
fi

if [[ $WITH_AGENTS_MD -eq 1 ]]; then
  echo ""
  echo "==> Removing always-on engineering rules..."
  bash "$REPO_DIR/scripts/install-agents-md.sh" --uninstall
fi

echo ""
echo "Done."
