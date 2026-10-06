#!/usr/bin/env bash
# install.sh — install all skills declared in registry.txt
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"

AGENT_ARG=""
WITH_AGENTS_MD=0
UPDATE_AGENTS=0
ALLOW_NON_MAIN=0
PLUGIN_OPT_IN=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      AGENT_ARG="$2"; shift 2 ;;
    --agent=*)
      AGENT_ARG="${1#*=}"; shift ;;
    --with-plugin)
      PLUGIN_OPT_IN+=("$2"); shift 2 ;;
    --with-plugin=*)
      PLUGIN_OPT_IN+=("${1#*=}"); shift ;;
    --with-agents-md)
      WITH_AGENTS_MD=1; shift ;;
    --update-agents)
      UPDATE_AGENTS=1; shift ;;
    --allow-non-main)
      ALLOW_NON_MAIN=1; shift ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

require_supported_os || exit 1
if [[ $ALLOW_NON_MAIN -eq 0 ]]; then
  require_main_checkout "$REPO_DIR" || exit 1
fi

# Save agent selection for update.sh to reuse
SELECTION_FILE="$(skills_runtime_dir "$REPO_DIR")/agent-selection.txt"

# A bare re-run replays the saved selection instead of prompting: the prompt's
# default (claude) would silently narrow every later update.sh on a multi-agent host.
if [[ -z "$AGENT_ARG" && -s "$SELECTION_FILE" ]]; then
  AGENT_ARG=$(cat "$SELECTION_FILE")
  echo "  using saved agent selection: $AGENT_ARG (pass --agent to change)"
fi

select_agents "$AGENT_ARG"

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
source "$(skills_runtime_dir "$REPO_DIR")/lib.sh"
migrate_keychain

INSTALLED_LIST="$(skills_runtime_dir "$REPO_DIR")/installed.txt"
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
        install_local_optional_skill "$id" "$REPO_DIR" "$target_dir" || true
        ;;
      *)
        echo "  WARNING: unknown type '$type' for '$id', skipping." >&2
        ;;
    esac
  done < "$REPO_DIR/registry.txt"
done

# polish-input is always wired, not opt-in: it ships as part of the `utils`
# group installed above, so its hook should be live wherever the skill is.
# wire_hook wires hooks into ~/.claude/settings.json or ~/.codex/hooks.json,
# skipping agents without supported settings paths (such as kiro or gemini).
echo ""
echo "==> Wiring hooks..."
for agent in "${SELECTED_AGENTS[@]}"; do
  wire_hook "polish-input" "$REPO_DIR" "$agent"
done

echo ""
echo "==> Configuring statusline for supported agents..."
for agent in "${SELECTED_AGENTS[@]}"; do
  install_statusline "$agent" "$REPO_DIR"
done

if [[ $WITH_AGENTS_MD -eq 1 ]]; then
  echo ""
  echo "==> Deploying always-on engineering rules..."
  bash "$REPO_DIR/scripts/install-agents-md.sh"
fi

# Agent CLI versions. Report only unless --update-agents: a fresh install should
# not silently upgrade a CLI out from under the person running it, and an upgrade
# can carry breaking changes. update.sh applies these automatically instead.
echo ""
echo "==> Agent CLI versions..."
if [[ $UPDATE_AGENTS -eq 1 ]]; then
  bash "$REPO_DIR/scripts/update-agents.sh" --apply || true
else
  bash "$REPO_DIR/scripts/update-agents.sh" || true
fi

echo ""
echo "==> Detecting outside agents..."
# Failure-tolerant: a missing outside agent must never block installing skills.
# OUTSIDE_AGENT_INIT=0 lets tests run install.sh without live agent probes.
if [[ "${OUTSIDE_AGENT_INIT:-1}" == "0" ]]; then
  echo "  skipped (OUTSIDE_AGENT_INIT=0)"
else
  bash "$(skills_runtime_dir "$REPO_DIR")/outside-agent.sh" init || echo "  WARNING: outside-agent init failed"
fi

# Print post-install hints when openspec is registered.
if grep -qE '^npm[[:space:]]+@fission-ai/openspec' "$REPO_DIR/registry.txt" 2>/dev/null; then
  echo ""
  echo "==> OpenSpec post-install steps (per target repo):"
  echo "    cd <your-repo> && openspec init --tools claude,kiro"
fi

echo ""
echo "Done. Run scripts/setup-credentials.sh to configure service credentials."
