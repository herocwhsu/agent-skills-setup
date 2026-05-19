#!/usr/bin/env bash
# uninstall.sh — remove all skills declared in registry.txt
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"

AGENT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)    AGENT_ARG="$2"; shift 2 ;;
    --agent=*)  AGENT_ARG="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

select_agents "$AGENT_ARG"

echo ""
echo "==> Removing skills from registry.txt..."

for agent in "${SELECTED_AGENTS[@]}"; do
  target_dir=$(agent_skills_dir "$agent")
  echo ""
  echo "  Agent: $agent → $target_dir"

  while IFS=' ' read -r type id subpath_or_empty; do
    case "$type" in
      ""|\#*) continue ;;
    esac

    case "$type" in
      pip)
        uninstall_pip_skill "$id" || true
        ;;
      github)
        uninstall_github_skill "$id" "${subpath_or_empty:-.}" "$target_dir" || true
        ;;
      local)
        uninstall_local_skill "$id" "$target_dir" || true
        ;;
      *)
        echo "  WARNING: unknown type '$type' for '$id', skipping." >&2
        ;;
    esac
  done < "$REPO_DIR/registry.txt"
done

echo ""
echo "Done."
