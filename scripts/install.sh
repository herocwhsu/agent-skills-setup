#!/usr/bin/env bash
# install.sh — install superpowers + custom skills for one or more agents
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_DIR/scripts/_lib.sh"

SUPERPOWERS_GITHUB="https://github.com/obra/superpowers/archive/refs/heads/main.zip"

# ---------------------------------------------------------------------------
# 1. Select target agents
# ---------------------------------------------------------------------------
select_agents

# ---------------------------------------------------------------------------
# 2. Install superpowers (upstream skills: brainstorming, TDD, etc.)
# ---------------------------------------------------------------------------
echo ""
echo "==> Installing superpowers skills..."

install_superpowers_to() {
  local target_dir="$1"
  mkdir -p "$target_dir"

  if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
    local pip_cmd
    pip_cmd=$(command -v pip3 || command -v pip)
    "$pip_cmd" install --quiet --upgrade agent-superpowers
    # agent-superpowers install writes to ~/.claude/skills by default;
    # for other agents we fall through to the zip method
    if [[ "$target_dir" == "$HOME/.claude/skills" ]]; then
      agent-superpowers install --skip-existing 2>/dev/null || true
      return
    fi
  fi

  # Fallback: download zip from GitHub
  echo "  pip not available or non-Claude target — downloading from GitHub..."
  local zip="/tmp/superpowers-main.zip"
  local extract="/tmp/superpowers-extract"
  download_file "$SUPERPOWERS_GITHUB" "$zip"
  rm -rf "$extract"
  unzip -q "$zip" -d "$extract"
  cp -rn "$extract/superpowers-main/skills/." "$target_dir/" 2>/dev/null || true
  rm -rf "$zip" "$extract"
  echo "  ✓ superpowers installed to $target_dir"
}

for agent in "${SELECTED_AGENTS[@]}"; do
  dir=$(agent_skills_dir "$agent")
  echo "  Agent: $agent → $dir"
  install_superpowers_to "$dir"
done

# ---------------------------------------------------------------------------
# 3. Install custom skills from manifest
# ---------------------------------------------------------------------------
echo ""
echo "==> Installing custom skills from manifest..."

while IFS= read -r skill; do
  [[ "$skill" =~ ^#|^[[:space:]]*$ ]] && continue
  src="$REPO_DIR/skills/$skill"
  if [[ ! -d "$src" ]]; then
    echo "  WARNING: skills/$skill not found in repo, skipping." >&2
    continue
  fi
  for agent in "${SELECTED_AGENTS[@]}"; do
    dir=$(agent_skills_dir "$agent")
    install_skill "$src" "$dir"
  done
done < "$REPO_DIR/manifest.txt"

# ---------------------------------------------------------------------------
# 4. Done
# ---------------------------------------------------------------------------
echo ""
echo "Done. Run scripts/setup-credentials.sh to configure credentials."
