#!/usr/bin/env bash
# validate-registry.sh — sanity-check registry.txt entries:
#   local            must have skills/<name>/SKILL.md
#   github-skill     must be <owner/repo> <skill-path> [name]
#   plugin           must be <owner/repo> <plugin-name> [marketplace-name]
# Usage: bash scripts/validate-registry.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${REGISTRY_FILE:-$REPO_DIR/registry.txt}"
SKILLS_DIR="$REPO_DIR/skills"

errors=0

while IFS=' ' read -r type id arg3 arg4; do
  case "$type" in
    ""|\#*) continue ;;
    local)
      skill_md="$SKILLS_DIR/$id/SKILL.md"
      if [[ ! -f "$skill_md" ]]; then
        echo "  ERROR: registry entry '$id' has no SKILL.md at $skill_md" >&2
        errors=$((errors + 1))
      fi
      ;;
    # local-optional entries are intentionally absent on some hosts — skip validation
    local-optional) continue ;;
    github-skill)
      if [[ "$id" != */* ]]; then
        echo "  ERROR: github-skill entry '$id' must be <owner>/<repo>" >&2
        errors=$((errors + 1))
      fi
      if [[ -z "$arg3" ]]; then
        echo "  ERROR: github-skill entry '$id' is missing the skill path (use \".\" for repo root)" >&2
        errors=$((errors + 1))
      fi
      ;;
    plugin)
      if [[ "$id" != */* ]]; then
        echo "  ERROR: plugin entry '$id' must be <owner>/<repo> (marketplace repo)" >&2
        errors=$((errors + 1))
      fi
      if [[ -z "$arg3" ]]; then
        echo "  ERROR: plugin entry '$id' is missing the plugin name" >&2
        errors=$((errors + 1))
      fi
      ;;
  esac
done < "$REGISTRY"

if [[ $errors -gt 0 ]]; then
  echo ""
  echo "Registry validation failed: $errors error(s). Fix registry.txt or create missing SKILL.md files." >&2
  exit 1
fi

echo "  ✓ registry.txt valid — all local entries have SKILL.md"
