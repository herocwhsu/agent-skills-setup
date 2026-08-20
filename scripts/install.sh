#!/usr/bin/env bash
# install.sh — install all skills declared in registry.txt
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"

AGENT_ARG=""
HOOK_SKILLS=()
WITH_AGENTS_MD=0
PLUGIN_OPT_IN=()
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
    --with-plugin)
      PLUGIN_OPT_IN+=("$2"); shift 2 ;;
    --with-plugin=*)
      PLUGIN_OPT_IN+=("${1#*=}"); shift ;;
    --with-agents-md)
      WITH_AGENTS_MD=1; shift ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

require_supported_os || exit 1

select_agents "$AGENT_ARG"

# Save agent selection for update.sh to reuse
SELECTION_FILE="$HOME/.agent-skills-setup/agent-selection.txt"
mkdir -p "$(dirname "$SELECTION_FILE")"
# Record every selected agent, not just the first, and compare against the
# agent list itself rather than a literal. Both halves of this were wrong:
# the test read "-eq 3" and broke silently the moment codex made it four, and
# the else-branch stored element 0, so a multi-agent install taught update.sh
# to refresh exactly one of them.
if [[ ${#SELECTED_AGENTS[@]} -eq ${#AGENTS[@]} ]]; then
  echo "all" > "$SELECTION_FILE"
else
  (IFS=','; echo "${SELECTED_AGENTS[*]}") > "$SELECTION_FILE"
fi
# Printed because this file drives every later update.sh: it replaces the
# previous selection rather than adding to it, so a narrow re-run silently
# narrowing future updates is exactly the failure to make visible.
echo "  agent selection recorded for update.sh: $(cat "$SELECTION_FILE")"

echo ""
echo "==> Validating registry..."
bash "$REPO_DIR/scripts/validate-registry.sh"

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

# Install global (non-agent-specific) packages once before the agent loop.
echo ""
echo "==> Installing global packages..."
while IFS=' ' read -r type id subpath_or_empty; do
  case "$type" in ""|\#*) continue ;; esac
  case "$type" in
    npm) install_npm_skill "$id" || true ;;
    pip) install_pip_skill "$id" "" || true ;;
  esac
done < "$REPO_DIR/registry.txt"

echo ""
echo "==> Installing per-agent skills from registry.txt..."

for agent in "${SELECTED_AGENTS[@]}"; do
  target_dir=$(agent_skills_dir "$agent")
  echo ""
  echo "  Agent: $agent → $target_dir"

  prune_dead_skill_links "$target_dir" "$REPO_DIR"

  # Kiro also gets prompt files and an auto-generated agent config
  if [[ "$agent" == "kiro" ]]; then
    install_kiro_prompts "$REPO_DIR"
    install_kiro_agent_config "$target_dir"
  fi

  while IFS=' ' read -r type id arg3 arg4; do
    # Skip comments and blank lines
    case "$type" in
      ""|\#*) continue ;;
    esac

    case "$type" in
      pip|npm)
        # Already handled in the global pass above
        ;;
      github)
        install_github_skill "$id" "${arg3:-.}" "$target_dir" || true
        ;;
      github-skill)
        install_github_single_skill "$id" "${arg3:-.}" "$target_dir" "${arg4:-}" || true
        ;;
      plugin)
        if [[ "$agent" == "claude" ]]; then
          install_claude_plugin "$id" "$arg3" "${arg4:-}" || true
        else
          echo "  plugin '$arg3' is Claude Code-only — skipped for $agent"
        fi
        ;;
      plugin-optional)
        if [[ "$agent" != "claude" ]]; then
          echo "  plugin '$arg3' is Claude Code-only — skipped for $agent"
        elif is_plugin_opt_in "$arg3"; then
          install_claude_plugin "$id" "$arg3" "${arg4:-}" || true
        else
          echo "  optional plugin '$arg3' not requested — install with --with-plugin $arg3"
        fi
        ;;
      local)
        install_local_skill "$id" "$REPO_DIR" "$target_dir" || true
        ;;
      local-optional)
        install_local_optional_skill "$id" "$REPO_DIR" "$target_dir"
        ;;
      *)
        echo "  WARNING: unknown type '$type' for '$id', skipping." >&2
        ;;
    esac
  done < "$REPO_DIR/registry.txt"
done

if [[ ${#HOOK_SKILLS[@]} -gt 0 ]]; then
  echo ""
  echo "==> Wiring hooks..."
  for skill in "${HOOK_SKILLS[@]}"; do
    for agent in "${SELECTED_AGENTS[@]}"; do
      wire_hook "$skill" "$REPO_DIR" "$agent"
    done
  done
fi

if [[ $WITH_AGENTS_MD -eq 1 ]]; then
  echo ""
  echo "==> Deploying always-on engineering rules..."
  bash "$REPO_DIR/scripts/install-agents-md.sh"
fi

# Print post-install hints when openspec is registered.
if grep -qE '^npm[[:space:]]+@fission-ai/openspec' "$REPO_DIR/registry.txt" 2>/dev/null; then
  echo ""
  echo "==> OpenSpec post-install steps (per target repo):"
  echo "    cd <your-repo> && openspec init --tools claude,kiro"
fi

echo ""
echo "Done. Run scripts/setup-credentials.sh to configure service credentials."
